import Foundation

public struct DevicePermissions: Codable, Sendable, Equatable {
    public var view: Bool
    public var input: Bool
    public var clipboard: Bool
    public var audio: Bool
    /// Cho phép thiết bị gửi lệnh mở khoá máy Mac thật (mặc định TẮT, Fail-Closed).
    public var unlock: Bool
    /// Cho phép gửi/nhận tệp 2 chiều với Mac (lưu vào ~/Downloads/Xdesk/). Mặc định TẮT, Fail-Closed.
    public var fileTransfer: Bool

    /// Thiết bị mới: xem + điều khiển bật; clipboard, âm thanh, mở khoá và truyền tệp tắt tới khi người dùng bật.
    public static let `default` = DevicePermissions(view: true, input: true, clipboard: false, audio: false, unlock: false, fileTransfer: false)

    public init(view: Bool, input: Bool, clipboard: Bool, audio: Bool, unlock: Bool = false, fileTransfer: Bool = false) {
        self.view = view
        self.input = input
        self.clipboard = clipboard
        self.audio = audio
        self.unlock = unlock
        self.fileTransfer = fileTransfer
    }

    private enum CodingKeys: String, CodingKey { case view, input, clipboard, audio, unlock, fileTransfer }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        view = try c.decode(Bool.self, forKey: .view)
        input = try c.decode(Bool.self, forKey: .input)
        clipboard = try c.decode(Bool.self, forKey: .clipboard)
        audio = try c.decode(Bool.self, forKey: .audio)
        unlock = try c.decodeIfPresent(Bool.self, forKey: .unlock) ?? false
        fileTransfer = try c.decodeIfPresent(Bool.self, forKey: .fileTransfer) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(view, forKey: .view)
        try c.encode(input, forKey: .input)
        try c.encode(clipboard, forKey: .clipboard)
        try c.encode(audio, forKey: .audio)
        // Chỉ ghi `unlock`/`fileTransfer` khi true để giữ nguyên HMAC của các file `paired-devices.json` cũ.
        if unlock { try c.encode(true, forKey: .unlock) }
        if fileTransfer { try c.encode(true, forKey: .fileTransfer) }
    }
}

/// Thiết bị đã ghép. JSON: `{id, name, pub (base64url), role, createdAt, lastSeen?, permissions}`.
public struct PairedDevice: Codable, Sendable, Equatable {
    /// Dấu vân tay `AB12-CD34-EF56-7890` của `publicKey`.
    public let id: String
    public var name: String
    public let publicKey: [UInt8]
    public var role: DeviceRole
    public let createdAt: Date
    public var lastSeen: Date?
    public var permissions: DevicePermissions
    /// Địa chỉ `host:port` gần nhất kết nối được (viewer lưu cho host đã biết); chỉ để gợi ý, không dùng để xác thực.
    public var lastAddress: String?

    public init(
        name: String, publicKey: [UInt8], role: DeviceRole, createdAt: Date,
        lastSeen: Date? = nil, permissions: DevicePermissions = .default
    ) {
        id = DeviceFingerprint.make(publicKey: publicKey)
        self.name = name
        self.publicKey = publicKey
        self.role = role
        self.createdAt = createdAt
        self.lastSeen = lastSeen
        self.permissions = permissions
    }

    private enum CodingKeys: String, CodingKey { case id, name, pub, role, createdAt, lastSeen, permissions, lastAddress }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let key = Base64URL.decode(try c.decode(String.self, forKey: .pub)), key.count == 32 else {
            throw DecodingError.dataCorruptedError(forKey: .pub, in: c, debugDescription: "pub must be 32-byte base64url")
        }
        id = DeviceFingerprint.make(publicKey: key)
        guard try c.decode(String.self, forKey: .id) == id else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "id does not match pub")
        }
        name = try c.decode(String.self, forKey: .name)
        publicKey = key
        role = try c.decode(DeviceRole.self, forKey: .role)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen)
        permissions = try c.decode(DevicePermissions.self, forKey: .permissions)
        lastAddress = try c.decodeIfPresent(String.self, forKey: .lastAddress)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(Base64URL.encode(publicKey), forKey: .pub)
        try c.encode(role, forKey: .role)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(lastSeen, forKey: .lastSeen)
        try c.encode(permissions, forKey: .permissions)
        try c.encodeIfPresent(lastAddress, forKey: .lastAddress)
    }
}
