import CryptoKit
import Foundation

/// Danh sách thiết bị đã ghép (`schemaVersion` 1), lưu lại sau mỗi thay đổi, có HMAC-SHA256 chống sửa file.
///
/// File = `{schemaVersion, devices, mac}`; `mac` = HMAC trên JSON chuẩn của `{schemaVersion, devices}` bằng khoá trong Keychain.
/// App host không sandbox nên tiến trình cùng user sửa được file; file sai MAC (hoặc thiếu MAC) bị bỏ: danh sách rỗng
/// và `integrityFailure == true` (fail-closed: không thiết bị nào được uỷ quyền, UI phải báo cho người dùng).
public actor PairedDevicesStore {
    public static let schemaVersion = 1
    /// File có bản ghi `unlockKey` ghi `schemaVersion` 2: bản cũ (chỉ hiểu 1) gặp file này sẽ ném `unsupportedSchema` và giữ nguyên file,
    /// thay vì ghi lại bản ghi thiếu `unlockKey` làm sai HMAC rồi cách ly file. Hạ cấp xuống bản cũ vì vậy không được hỗ trợ.
    public static let unlockKeySchemaVersion = 2
    /// Cửa sổ cho phép đăng ký khoá mở khoá sau khi người dùng bật quyền "Mở khoá Mac" hoặc bấm "Đặt lại khoá".
    public static let unlockEnrollmentWindow: TimeInterval = 300

    private struct FileContents: Codable {
        var schemaVersion: Int
        var devices: [PairedDevice]
        var mac: String?
    }

    private let storage: any PairedDevicesStorage
    private let macKey: SymmetricKey
    private let now: @Sendable () -> Date
    private var byId: [String: PairedDevice]
    /// `true` nếu file có trên đĩa nhưng MAC sai/thiếu và đã bị bỏ qua; lần ghi kế tiếp sẽ thay file đó.
    public private(set) var integrityFailure = false
    /// Sticky: file danh sách từng bị sửa/hỏng MAC trong phiên này. UI báo cho tới khi gọi `acknowledgeIntegrityNotice()`.
    public private(set) var integrityNoticePending = false
    private var needsQuarantine = false
    private var observers: [UUID: AsyncStream<Change>.Continuation] = [:]
    /// Hạn của cửa sổ đăng ký khoá theo thiết bị; chỉ trong bộ nhớ (khởi động lại = đóng, fail-closed).
    private var enrollmentDeadlines: [String: Date] = [:]

    public enum Change: Sendable, Equatable {
        case added(String)
        case removed(String)
        case permissionsChanged(String)
    }

    /// Ném `corrupt` nếu file hỏng/trùng id và `unsupportedSchema` nếu file do bản mới hơn ghi (không bao giờ tự xoá file).
    public init(
        storage: any PairedDevicesStorage, macKey: any PairedDevicesMACKeyProviding,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        self.storage = storage
        self.now = now
        self.macKey = try macKey.loadOrCreate()
        byId = [:]
        guard let data = try storage.read() else { return }
        var contents: FileContents
        do { contents = try Self.decoder.decode(FileContents.self, from: data) } catch { throw IdentityStoreError.corrupt }
        guard [Self.schemaVersion, Self.unlockKeySchemaVersion].contains(contents.schemaVersion) else { throw IdentityStoreError.unsupportedSchema(contents.schemaVersion) }
        guard Set(contents.devices.map(\.id)).count == contents.devices.count else { throw IdentityStoreError.corrupt }
        let mac = contents.mac.flatMap(Base64URL.decode)
        contents.mac = nil
        guard let mac, let canonical = try? Self.encoder.encode(contents),
              PairedDevicesIntegrity.isValid(mac, for: canonical, key: self.macKey)
        else {
            integrityFailure = true
            integrityNoticePending = true
            needsQuarantine = true
            return
        }
        byId = Dictionary(uniqueKeysWithValues: contents.devices.map { ($0.id, $0) })
    }

    public var devices: [PairedDevice] { byId.values.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) } }

    /// Tìm theo khoá công khai đầy đủ 32 byte, so sánh hằng thời gian trên toàn danh sách (không dừng sớm).
    /// Dấu vân tay 64 bit chỉ để hiển thị/định danh, không bao giờ đủ để uỷ quyền.
    public func device(publicKey: [UInt8]) -> PairedDevice? {
        var found: PairedDevice?
        for device in byId.values where ConstantTime.equals(device.publicKey, publicKey) { found = device }
        return found
    }

    /// Thêm thiết bị; nếu khoá đã có thì chỉ cập nhật tên/vai trò và giữ quyền hiện tại.
    /// Trùng `id` (fingerprint) nhưng khác khoá → `deviceIdCollision`, danh sách không đổi.
    /// Luồng thay đổi danh sách (thêm/xoá/đổi quyền) để host cắt phiên của thiết bị bị thu hồi. Mỗi lần gọi một luồng riêng.
    public func changes() -> AsyncStream<Change> {
        let token = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: Change.self)
        observers[token] = continuation
        continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(token) } }
        return stream
    }

    public func acknowledgeIntegrityNotice() { integrityNoticePending = false }

    private func removeObserver(_ token: UUID) { observers[token] = nil }

    private func notify(_ change: Change) { for continuation in observers.values { continuation.yield(change) } }

    @discardableResult
    public func add(name: String, publicKey: [UInt8], role: DeviceRole) throws -> PairedDevice {
        guard publicKey.count == 32 else { throw CryptoError.invalidPublicKey }
        let id = DeviceFingerprint.make(publicKey: publicKey)
        if let existing = byId[id], !ConstantTime.equals(existing.publicKey, publicKey) { throw CryptoError.deviceIdCollision }
        var device = byId[id] ?? PairedDevice(name: name, publicKey: publicKey, role: role, createdAt: now())
        device.name = name
        device.role = role
        let isNew = byId[id] == nil
        try commit(device)
        if isNew { notify(.added(id)) }
        return device
    }

    /// Thu hồi thiết bị; trả `false` nếu không có.
    @discardableResult
    public func remove(id: String) throws -> Bool {
        guard let removed = byId.removeValue(forKey: id) else { return false }
        do { try save() } catch {
            byId[id] = removed
            throw error
        }
        notify(.removed(id))
        return true
    }

    public func setPermissions(id: String, _ permissions: DevicePermissions) throws {
        guard var device = byId[id] else { return }
        // Tắt quyền mở khoá = thu hồi khoá sinh trắc học; lần bật lại sẽ đăng ký khoá mới.
        if device.permissions.unlock, !permissions.unlock {
            device.unlockKey = nil
            enrollmentDeadlines[id] = nil
        }
        if !device.permissions.unlock, permissions.unlock { openUnlockEnrollment(id: id) }
        device.permissions = permissions
        try commit(device)
        notify(.permissionsChanged(id))
    }

    /// Kết quả đăng ký khoá mở khoá của điện thoại (TOFU, fail-closed).
    public enum UnlockKeyEnrollment: Sendable, Equatable {
        case enrolled
        case alreadyEnrolled
        /// Thiết bị đã có một khoá khác; giữ khoá cũ, cần người dùng đặt lại trên Mac.
        case mismatch
        case notPermitted
        /// Chưa có thao tác của người dùng trên Mac (bật quyền / "Đặt lại khoá") trong 5 phút gần đây.
        case windowClosed
        case invalidKey
    }

    /// Mở cửa sổ đăng ký khoá 5 phút cho thiết bị (gọi khi người dùng Mac bật quyền hoặc đặt lại khoá).
    public func openUnlockEnrollment(id: String) {
        enrollmentDeadlines[id] = now().addingTimeInterval(Self.unlockEnrollmentWindow)
    }

    /// Chỉ đăng ký khi thiết bị đang có quyền `unlock`, chưa có khoá và cửa sổ đăng ký đang mở. Khoá khác khoá đã lưu không bao giờ ghi đè.
    public func enrollUnlockKey(id: String, key: [UInt8]) throws -> UnlockKeyEnrollment {
        guard UnlockKeyFormat.isValid(key) else { return .invalidKey }
        guard var device = byId[id], device.permissions.unlock else { return .notPermitted }
        if let existing = device.unlockKey { return ConstantTime.equals(existing, key) ? .alreadyEnrolled : .mismatch }
        guard let deadline = enrollmentDeadlines[id], now() <= deadline else { return .windowClosed }
        enrollmentDeadlines[id] = nil
        device.unlockKey = key
        try commit(device)
        return .enrolled
    }

    /// "Đặt lại khoá": xoá khoá đã đăng ký (nếu có) và mở cửa sổ 5 phút để `unlock.key` kế tiếp đăng ký lại.
    public func clearUnlockKey(id: String) throws {
        guard var device = byId[id] else { return }
        if device.unlockKey != nil {
            device.unlockKey = nil
            try commit(device)
        }
        if device.permissions.unlock { openUnlockEnrollment(id: id) }
    }

    public func setLastAddress(id: String, _ address: String) throws {
        guard var device = byId[id], device.lastAddress != address else { return }
        device.lastAddress = address
        try commit(device)
    }

    public func markSeen(id: String) throws {
        guard var device = byId[id] else { return }
        device.lastSeen = now()
        try commit(device)
    }

    private func commit(_ device: PairedDevice) throws {
        let previous = byId[device.id]
        byId[device.id] = device
        do { try save() } catch {
            byId[device.id] = previous
            throw error
        }
    }

    private func save() throws {
        let version = devices.contains { $0.unlockKey != nil } ? Self.unlockKeySchemaVersion : Self.schemaVersion
        var contents = FileContents(schemaVersion: version, devices: devices, mac: nil)
        let canonical = try Self.encoder.encode(contents)
        contents.mac = Base64URL.encode(PairedDevicesIntegrity.mac(for: canonical, key: macKey))
        if needsQuarantine {
            try storage.quarantine()
            needsQuarantine = false
        }
        try storage.write(Self.encoder.encode(contents))
        integrityFailure = false
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
