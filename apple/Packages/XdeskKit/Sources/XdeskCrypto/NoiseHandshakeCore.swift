import CryptoKit

/// Lõi HandshakeState của Noise (rev 34 §5.3), dạng struct copy được để mỗi message áp dụng kiểu "tất cả hoặc không gì":
/// lỗi giữa chừng không làm hỏng trạng thái cũ. Chỉ dùng nội bộ; ngoài module chỉ thấy `NoiseHandshakeState` (~Copyable),
/// nên không ai giữ được bản sao có cùng khoá/bộ đếm nonce.
struct NoiseHandshakeCore: Sendable {
    static let maxMessageLength = 65535
    static let keyLength = 32

    let pattern: NoisePattern
    let role: NoiseRole
    var symmetric: NoiseSymmetricState
    let staticKey: Curve25519.KeyAgreement.PrivateKey
    var ephemeralKey: Curve25519.KeyAgreement.PrivateKey?
    var remoteStatic: Curve25519.KeyAgreement.PublicKey?
    var remoteEphemeral: Curve25519.KeyAgreement.PublicKey?
    let psk: [UInt8]?
    var nextMessage = 0
    /// Khoá ephemeral cố định cho test vector; luôn nil ở đường chạy thật.
    let ephemeralOverride: Curve25519.KeyAgreement.PrivateKey?
    /// Cho phép payload ở message 0 của XX/XXpsk3 (chỉ để chạy vector công khai của cacophony).
    let allowFirstMessagePayload: Bool
    /// Handshake hash ngay sau message 2: đầu vào SAS, không phụ thuộc nội dung message 3 do initiator chọn.
    private(set) var messageTwoHash: [UInt8]?

    init(
        pattern: NoisePattern, role: NoiseRole, staticKey: Curve25519.KeyAgreement.PrivateKey,
        remoteStaticKey: [UInt8]?, psk: [UInt8]?, prologue: [UInt8],
        ephemeralOverride: Curve25519.KeyAgreement.PrivateKey? = nil, allowFirstMessagePayload: Bool = false
    ) throws {
        if pattern.usesPresharedKey {
            guard let psk else { throw CryptoError.missingPresharedKey }
            guard psk.count == Self.keyLength else { throw CryptoError.invalidPresharedKeyLength }
        } else if psk != nil {
            throw CryptoError.unexpectedKeyForPattern
        }
        let needsRemote = pattern.initiatorKnowsResponderStatic && role == .initiator
        if needsRemote, remoteStaticKey == nil { throw CryptoError.missingRemoteStaticKey }
        if !needsRemote, remoteStaticKey != nil { throw CryptoError.unexpectedKeyForPattern }

        self.pattern = pattern
        self.role = role
        self.staticKey = staticKey
        self.psk = psk
        self.ephemeralOverride = ephemeralOverride
        self.allowFirstMessagePayload = allowFirstMessagePayload
        remoteStatic = try remoteStaticKey.map(Self.publicKey)
        symmetric = NoiseSymmetricState(protocolName: pattern.protocolName)
        symmetric.mixHash(prologue)
        if pattern.initiatorKnowsResponderStatic {
            // Pre-message `<- s`: cả hai bên băm khoá tĩnh của responder.
            let responderStatic = role == .initiator ? remoteStatic : staticKey.publicKey
            symmetric.mixHash(responderStatic.map { Array($0.rawRepresentation) } ?? [])
        }
    }

    var isComplete: Bool { nextMessage == pattern.messageCount }
    var isMyTurnToWrite: Bool { (nextMessage % 2 == 0) == (role == .initiator) }

    /// Message 0 của XX/XXpsk3 chưa có khoá bí mật (psk3 chỉ khoá từ `e` công khai) nên payload phải rỗng.
    private var firstPayloadMustBeEmpty: Bool { nextMessage == 0 && pattern != .ik && !allowFirstMessagePayload }

    mutating func writeMessage(payload: [UInt8]) throws -> [UInt8] {
        guard !isComplete else { throw CryptoError.handshakeComplete }
        guard isMyTurnToWrite else { throw CryptoError.wrongTurn }
        if firstPayloadMustBeEmpty, !payload.isEmpty { throw CryptoError.invalidHandshakePayload }
        var copy = self
        var out: [UInt8] = []
        for token in pattern.messages[nextMessage] { try copy.write(token, into: &out) }
        out += try copy.symmetric.encryptAndHash(payload)
        guard out.count <= Self.maxMessageLength else { throw CryptoError.messageTooLarge }
        copy.finishMessage()
        self = copy
        return out
    }

    mutating func readMessage(_ message: [UInt8]) throws -> [UInt8] {
        guard !isComplete else { throw CryptoError.handshakeComplete }
        guard !isMyTurnToWrite else { throw CryptoError.wrongTurn }
        guard message.count <= Self.maxMessageLength else { throw CryptoError.messageTooLarge }
        var copy = self
        var offset = 0
        for token in pattern.messages[nextMessage] { try copy.read(token, from: message, offset: &offset) }
        let payload = try copy.symmetric.decryptAndHash(Array(message[offset...]))
        if copy.firstPayloadMustBeEmpty, !payload.isEmpty { throw CryptoError.invalidHandshakePayload }
        copy.finishMessage()
        self = copy
        return payload
    }

    func splitKeys() throws -> (SymmetricKey, SymmetricKey) {
        guard isComplete else { throw CryptoError.handshakeIncomplete }
        return symmetric.split()
    }

    private mutating func finishMessage() {
        nextMessage += 1
        if nextMessage == 2 { messageTwoHash = symmetric.hash }
    }
}
