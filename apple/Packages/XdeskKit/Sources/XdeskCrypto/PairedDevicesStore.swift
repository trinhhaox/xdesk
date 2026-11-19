import CryptoKit
import Foundation

/// Danh sách thiết bị đã ghép (`schemaVersion` 1), lưu lại sau mỗi thay đổi, có HMAC-SHA256 chống sửa file.
///
/// File = `{schemaVersion, devices, mac}`; `mac` = HMAC trên JSON chuẩn của `{schemaVersion, devices}` bằng khoá trong Keychain.
/// App host không sandbox nên tiến trình cùng user sửa được file; file sai MAC (hoặc thiếu MAC) bị bỏ: danh sách rỗng
/// và `integrityFailure == true` (fail-closed: không thiết bị nào được uỷ quyền, UI phải báo cho người dùng).
public actor PairedDevicesStore {
    public static let schemaVersion = 1

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
        guard contents.schemaVersion == Self.schemaVersion else { throw IdentityStoreError.unsupportedSchema(contents.schemaVersion) }
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
        device.permissions = permissions
        try commit(device)
        notify(.permissionsChanged(id))
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
        var contents = FileContents(schemaVersion: Self.schemaVersion, devices: devices, mac: nil)
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
