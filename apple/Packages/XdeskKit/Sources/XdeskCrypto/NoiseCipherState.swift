import CryptoKit

enum ChaChaNonce {
    /// Nonce 12 byte theo Noise: 4 byte 0 | counter u64 little-endian.
    static func make(counter: UInt64) throws -> ChaChaPoly.Nonce {
        var bytes = [UInt8](repeating: 0, count: 12)
        for i in 0..<8 { bytes[4 + i] = UInt8(truncatingIfNeeded: counter >> (8 * UInt64(i))) }
        do { return try ChaChaPoly.Nonce(data: bytes) } catch { throw CryptoError.invalidLength }
    }
}

extension SymmetricKey {
    var bytes: [UInt8] { withUnsafeBytes { Array($0) } }
}

/// CipherState của Noise (rev 34 §5.1): khoá tuỳ chọn + bộ đếm nonce 64-bit tăng mỗi lần thành công.
struct NoiseCipherState: Sendable {
    private(set) var key: SymmetricKey?
    private(set) var nonce: UInt64 = 0

    init(key: SymmetricKey? = nil) { self.key = key }

    var hasKey: Bool { key != nil }

    mutating func initializeKey(_ newKey: SymmetricKey?) {
        key = newKey
        nonce = 0
    }

    mutating func encrypt(ad: [UInt8], plaintext: [UInt8]) throws -> [UInt8] {
        guard let key else { return plaintext }
        guard nonce != UInt64.max else { throw CryptoError.nonceExhausted }
        let box = try ChaChaPoly.seal(plaintext, using: key, nonce: ChaChaNonce.make(counter: nonce), authenticating: ad)
        nonce += 1
        return Array(box.ciphertext) + Array(box.tag)
    }

    mutating func decrypt(ad: [UInt8], ciphertext: [UInt8]) throws -> [UInt8] {
        guard let key else { return ciphertext }
        guard nonce != UInt64.max else { throw CryptoError.nonceExhausted }
        guard ciphertext.count >= 16 else { throw CryptoError.messageTooShort }
        let split = ciphertext.count - 16
        do {
            let box = try ChaChaPoly.SealedBox(
                nonce: ChaChaNonce.make(counter: nonce),
                ciphertext: ciphertext[0..<split],
                tag: ciphertext[split...]
            )
            let plaintext = try ChaChaPoly.open(box, using: key, authenticating: ad)
            nonce += 1
            return Array(plaintext)
        } catch { throw CryptoError.authenticationFailed }
    }
}
