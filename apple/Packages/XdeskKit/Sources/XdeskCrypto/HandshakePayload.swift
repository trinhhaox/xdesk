import Foundation

/// Vai trò của thiết bị trong phiên: host chia sẻ màn hình, viewer xem/điều khiển.
public enum DeviceRole: UInt8, Sendable, Codable {
    case host = 0
    case viewer = 1
}

/// Payload (mã hoá) của message bắt tay mang danh tính ứng dụng:
/// `u8 ver=1 | u8 role | u8 flags | u8 nameLen | name UTF-8 | [nonce 16 B nếu flags bit0]`.
public struct HandshakePayload: Sendable, Equatable {
    public static let version: UInt8 = 1
    public static let maxNameLength = 64
    private static let hasSasNonce: UInt8 = 0x01

    public var role: DeviceRole
    public var deviceName: String
    /// Nonce SAS của initiator trong message 3 của XX (xem `ShortAuthString`).
    public var sasNonce: [UInt8]?

    public init(role: DeviceRole, deviceName: String, sasNonce: [UInt8]? = nil) {
        self.role = role
        self.deviceName = deviceName
        self.sasNonce = sasNonce
    }

    public func encode() throws -> [UInt8] {
        let name = Array(deviceName.utf8)
        guard name.count <= Self.maxNameLength else { throw CryptoError.invalidHandshakePayload }
        if let sasNonce, sasNonce.count != ShortAuthString.nonceLength { throw CryptoError.invalidHandshakePayload }
        let flags: UInt8 = sasNonce == nil ? 0 : Self.hasSasNonce
        return [Self.version, role.rawValue, flags, UInt8(name.count)] + name + (sasNonce ?? [])
    }

    public static func decode(_ bytes: [UInt8]) throws -> HandshakePayload {
        guard bytes.count >= 4, bytes[0] == version, bytes[2] & ~hasSasNonce == 0,
              let role = DeviceRole(rawValue: bytes[1]) else { throw CryptoError.invalidHandshakePayload }
        let nameLength = Int(bytes[3])
        let hasNonce = bytes[2] & hasSasNonce != 0
        let expected = 4 + nameLength + (hasNonce ? ShortAuthString.nonceLength : 0)
        guard nameLength <= maxNameLength, bytes.count == expected,
              let name = String(data: Data(bytes[4..<4 + nameLength]), encoding: .utf8)
        else { throw CryptoError.invalidHandshakePayload }
        return HandshakePayload(
            role: role, deviceName: name, sasNonce: hasNonce ? Array(bytes[(4 + nameLength)...]) : nil)
    }
}
