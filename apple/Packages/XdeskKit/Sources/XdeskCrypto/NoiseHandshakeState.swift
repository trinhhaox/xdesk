import CryptoKit

/// HandshakeState của Noise (rev 34 §5.3).
///
/// `~Copyable` có chủ đích (rà soát bảo mật M2): bản sao giữ cùng khoá/bộ đếm nonce sẽ cho phép mã hoá hai bản rõ khác nhau
/// dưới cùng (khoá, nonce). Kiểu không-copy được còn không thể truyền vào `print`/`dump`/nội suy chuỗi (cần `Any`), nên
/// psk và khoá riêng không lọt vào log qua reflection. Struct nội bộ `NoiseHandshakeCore` vẫn copy được để rollback từng message.
public struct NoiseHandshakeState: ~Copyable, Sendable {
    public static let maxMessageLength = NoiseHandshakeCore.maxMessageLength
    public static let keyLength = NoiseHandshakeCore.keyLength
    /// Prologue cố định của Xdesk wire v1; hai bên khác prologue thì bắt tay thất bại.
    public static let defaultPrologue = Array("xdesk-wire-v1".utf8)

    private var core: NoiseHandshakeCore

    // Deinit tường minh: huỷ qua hàm của XdeskCrypto, không để module khác inline việc huỷ các kiểu nội bộ (lỗi liên kết Release).
    deinit {}

    public init(
        pattern: NoisePattern,
        role: NoiseRole,
        staticKey: Curve25519.KeyAgreement.PrivateKey,
        remoteStaticKey: [UInt8]? = nil,
        psk: [UInt8]? = nil,
        prologue: [UInt8] = NoiseHandshakeState.defaultPrologue
    ) throws {
        core = try NoiseHandshakeCore(
            pattern: pattern, role: role, staticKey: staticKey, remoteStaticKey: remoteStaticKey, psk: psk, prologue: prologue)
    }

    /// Dành cho test vector: khoá ephemeral cố định và cho phép payload ở message 0 (vector cacophony có payload).
    init(
        pattern: NoisePattern, role: NoiseRole, staticKey: Curve25519.KeyAgreement.PrivateKey,
        remoteStaticKey: [UInt8]?, psk: [UInt8]?, prologue: [UInt8],
        ephemeralOverride: Curve25519.KeyAgreement.PrivateKey
    ) throws {
        core = try NoiseHandshakeCore(
            pattern: pattern, role: role, staticKey: staticKey, remoteStaticKey: remoteStaticKey, psk: psk,
            prologue: prologue, ephemeralOverride: ephemeralOverride, allowFirstMessagePayload: true)
    }

    public var pattern: NoisePattern { core.pattern }
    public var role: NoiseRole { core.role }
    public var isComplete: Bool { core.isComplete }
    public var handshakeHash: [UInt8] { core.symmetric.hash }
    /// Hash ngay sau message 2 (có sau khi viết/đọc message 2). Đầu vào của `ShortAuthString.code`.
    public var messageTwoHash: [UInt8]? { core.messageTwoHash }
    /// Khoá tĩnh của đối tác; có sau khi đọc message mang `s` (hoặc ngay từ đầu với initiator IK).
    public var remoteStaticKey: [UInt8]? { core.remoteStatic.map { Array($0.rawRepresentation) } }
    /// Khoá ephemeral của đối tác; có sau khi đọc message mang `e`.
    public var remoteEphemeralKey: [UInt8]? { core.remoteEphemeral.map { Array($0.rawRepresentation) } }
    /// Khoá ephemeral của mình; có sau khi viết message mang `e`.
    public var localEphemeralKey: [UInt8]? { core.ephemeralKey.map { Array($0.publicKey.rawRepresentation) } }

    /// Message 0 của XX/XXpsk3 không được mang payload (chưa mã hoá): ném `invalidHandshakePayload`.
    public mutating func writeMessage(payload: [UInt8] = []) throws -> [UInt8] {
        try core.writeMessage(payload: payload)
    }

    public mutating func readMessage(_ message: [UInt8]) throws -> [UInt8] {
        try core.readMessage(message)
    }

    /// Hai khoá truyền tải thô (i→r, r→i). Dùng `sessionKeys()` để ra khoá TCP/UDP.
    public func splitKeys() throws -> (initiatorToResponder: SymmetricKey, responderToInitiator: SymmetricKey) {
        let keys = try core.splitKeys()
        return (keys.0, keys.1)
    }
}
