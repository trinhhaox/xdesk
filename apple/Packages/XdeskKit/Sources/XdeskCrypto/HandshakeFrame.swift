/// Nội dung frame TCP `kind 0x01` (Handshake): `u8 type | body`.
/// - `begin` (0x00): `u8 wireMajor=1 | u8 pattern` — initiator gửi đầu tiên, báo pattern sẽ chạy.
/// - `commit` (0x01): 32 B cam kết SAS, chỉ khi pattern XX, gửi ngay sau `begin`, trước message 1.
/// - `noise` (0x02): một message Noise nguyên vẹn.
public enum HandshakeFrame: Sendable, Equatable {
    case begin(NoisePattern)
    case commit([UInt8])
    case noise([UInt8])

    public static let wireMajor: UInt8 = 1

    public func encode() -> [UInt8] {
        switch self {
        case .begin(let pattern): [0x00, Self.wireMajor, pattern.rawValue]
        case .commit(let commitment): [0x01] + commitment
        case .noise(let message): [0x02] + message
        }
    }

    public static func decode(_ bytes: [UInt8]) throws -> HandshakeFrame {
        guard let type = bytes.first else { throw CryptoError.invalidHandshakeFrame }
        let body = Array(bytes.dropFirst())
        switch type {
        case 0x00:
            guard body.count == 2, body[0] == wireMajor, let pattern = NoisePattern(rawValue: body[1])
            else { throw CryptoError.invalidHandshakeFrame }
            return .begin(pattern)
        case 0x01:
            guard body.count == 32 else { throw CryptoError.invalidHandshakeFrame }
            return .commit(body)
        case 0x02:
            guard !body.isEmpty, body.count <= NoiseHandshakeState.maxMessageLength else { throw CryptoError.invalidHandshakeFrame }
            return .noise(body)
        default:
            throw CryptoError.invalidHandshakeFrame
        }
    }
}
