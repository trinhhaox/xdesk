import Foundation

/// Host thêm bằng địa chỉ (Tailscale `100.x.y.z`, MagicDNS, IP LAN) vì Bonjour không đi qua Tailscale.
public struct ManualHost: Codable, Sendable, Equatable, Identifiable {
    /// Địa chỉ người dùng nhập, dạng chuẩn `host:port`.
    public let address: String
    public var name: String
    /// IP:cổng thực lần kết nối thành công gần nhất (để biết tên MagicDNS đang trỏ tới đâu, hoặc nhập lại bằng IP).
    public var lastAddress: String?
    public var lastConnected: Date?

    public var id: String { address }
}

public enum ManualHostError: Error, Equatable, LocalizedError {
    case invalidAddress
    case limitReached

    public var errorDescription: String? {
        switch self {
        case .invalidAddress: String(localized: "Địa chỉ không hợp lệ. Nhập IP (100.x.y.z) hoặc tên máy, tuỳ chọn thêm :cổng.", bundle: .module)
        case .limitReached: String(localized: "Đã đủ \(String(ManualHostStore.maxHosts)) máy; hãy xoá bớt trước khi thêm.", bundle: .module)
        }
    }
}

/// Danh sách host nhập tay, lưu JSON (`schemaVersion` 1). Không phải bí mật: kẻ sửa file chỉ đổi được nơi kết nối tới,
/// còn danh tính host vẫn do Noise (khoá đã ghép) xác thực.
public actor ManualHostStore {
    public static let maxHosts = 50
    private static let schemaVersion = 1

    private struct File: Codable {
        var schemaVersion: Int
        var hosts: [ManualHost]
    }

    private let fileURL: URL
    private var items: [ManualHost] = []
    /// Lý do không đọc được file cũ (hỏng/lạ phiên bản); file đó được giữ lại với đuôi `.bad`.
    public private(set) var loadError: String?

    public init(fileURL: URL) {
        self.fileURL = fileURL
        do {
            if let data = try? Data(contentsOf: fileURL) {
                let file = try JSONDecoder.manualHosts.decode(File.self, from: data)
                guard file.schemaVersion == Self.schemaVersion else { throw ManualHostError.invalidAddress }
                items = file.hosts
            }
        } catch {
            loadError = String(localized: "Không đọc được danh sách máy nhập tay (\(fileURL.lastPathComponent)); đã giữ bản cũ với đuôi .bad.", bundle: .module)
            try? FileManager.default.moveItem(at: fileURL, to: fileURL.appendingPathExtension("bad"))
        }
    }

    public static func openDefault() throws -> ManualHostStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return ManualHostStore(fileURL: base.appendingPathComponent("Xdesk", isDirectory: true).appendingPathComponent("manual-hosts.json"))
    }

    /// Mới dùng gần nhất lên đầu, chưa từng kết nối theo thứ tự thêm.
    public var hosts: [ManualHost] {
        items.sorted { ($0.lastConnected ?? .distantPast) > ($1.lastConnected ?? .distantPast) }
    }

    @discardableResult
    public func add(address text: String, name: String? = nil) throws -> ManualHost {
        guard let parsed = ManualHostAddress(text) else { throw ManualHostError.invalidAddress }
        let label = name.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : String($0.prefix(64)) } ?? parsed.host
        if let index = items.firstIndex(where: { $0.address == parsed.normalized }) {
            items[index].name = label
            try save()
            return items[index]
        }
        guard items.count < Self.maxHosts else { throw ManualHostError.limitReached }
        let host = ManualHost(address: parsed.normalized, name: label)
        items.append(host)
        try save()
        return host
    }

    public func remove(address: String) throws {
        let before = items.count
        items.removeAll { $0.address == address }
        if items.count != before { try save() }
    }

    /// Ghi nhận kết nối thành công: `resolved` = IP:cổng thực của host (chỉ lưu khi hợp lệ).
    public func recordConnection(address: String, resolved: String?, at date: Date = Date()) throws {
        guard let index = items.firstIndex(where: { $0.address == address }) else { return }
        items[index].lastConnected = date
        items[index].lastAddress = resolved.flatMap { ManualHostAddress($0)?.normalized }
        try save()
    }

    private func save() throws {
        let data = try JSONEncoder.manualHosts.encode(File(schemaVersion: Self.schemaVersion, hosts: items))
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: fileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var manualHosts: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var manualHosts: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
