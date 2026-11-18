import CryptoKit

extension NoiseHandshakeCore {
    mutating func write(_ token: NoiseToken, into out: inout [UInt8]) throws {
        switch token {
        case .e:
            let key = ephemeralOverride ?? Curve25519.KeyAgreement.PrivateKey()
            ephemeralKey = key
            let publicBytes = Array(key.publicKey.rawRepresentation)
            out += publicBytes
            mixEphemeral(publicBytes)
        case .s:
            out += try symmetric.encryptAndHash(Array(staticKey.publicKey.rawRepresentation))
        case .psk:
            try mixPsk()
        default:
            try mixDiffieHellman(token)
        }
    }

    mutating func read(_ token: NoiseToken, from message: [UInt8], offset: inout Int) throws {
        switch token {
        case .e:
            let bytes = try Self.take(Self.keyLength, from: message, offset: &offset)
            remoteEphemeral = try Self.publicKey(bytes)
            mixEphemeral(bytes)
        case .s:
            let length = Self.keyLength + (symmetric.hasKey ? 16 : 0)
            let bytes = try symmetric.decryptAndHash(Self.take(length, from: message, offset: &offset))
            remoteStatic = try Self.publicKey(bytes)
        case .psk:
            try mixPsk()
        default:
            try mixDiffieHellman(token)
        }
    }

    private mutating func mixEphemeral(_ publicBytes: [UInt8]) {
        symmetric.mixHash(publicBytes)
        if pattern.usesPresharedKey { symmetric.mixKey(publicBytes) }
    }

    private mutating func mixPsk() throws {
        guard let psk else { throw CryptoError.missingPresharedKey }
        symmetric.mixKeyAndHash(psk)
    }

    private mutating func mixDiffieHellman(_ token: NoiseToken) throws {
        let isInitiator = role == .initiator
        let pair: (Curve25519.KeyAgreement.PrivateKey?, Curve25519.KeyAgreement.PublicKey?)
        switch token {
        case .ee: pair = (ephemeralKey, remoteEphemeral)
        case .es: pair = isInitiator ? (ephemeralKey, remoteStatic) : (staticKey, remoteEphemeral)
        case .se: pair = isInitiator ? (staticKey, remoteEphemeral) : (ephemeralKey, remoteStatic)
        default: pair = (staticKey, remoteStatic)
        }
        guard let privateKey = pair.0, let publicKey = pair.1 else { throw CryptoError.handshakeIncomplete }
        let secret: [UInt8]
        // CryptoKit tự ném lỗi với điểm bậc thấp; gói về CryptoError. Kiểm toàn số 0 vẫn giữ để cổng Kotlin/JCA có cùng hành vi.
        do { secret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey).withUnsafeBytes { Array($0) } } catch {
            throw CryptoError.invalidDiffieHellman
        }
        guard !ConstantTime.isAllZero(secret) else { throw CryptoError.invalidDiffieHellman }
        symmetric.mixKey(secret)
    }

    static func publicKey(_ bytes: [UInt8]) throws -> Curve25519.KeyAgreement.PublicKey {
        guard bytes.count == keyLength else { throw CryptoError.invalidPublicKey }
        do { return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: bytes) } catch { throw CryptoError.invalidPublicKey }
    }

    static func take(_ count: Int, from message: [UInt8], offset: inout Int) throws -> [UInt8] {
        guard message.count - offset >= count else { throw CryptoError.messageTooShort }
        defer { offset += count }
        return Array(message[offset..<offset + count])
    }
}
