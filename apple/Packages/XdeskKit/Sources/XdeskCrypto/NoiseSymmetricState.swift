import CryptoKit

/// SymmetricState của Noise (rev 34 §5.2) với HASH = SHA-256.
struct NoiseSymmetricState: Sendable {
    private var chainingKey: [UInt8]
    private(set) var hash: [UInt8]
    private var cipher = NoiseCipherState()

    init(protocolName: String) {
        let name = Array(protocolName.utf8)
        hash = name.count <= 32 ? name + [UInt8](repeating: 0, count: 32 - name.count) : Array(SHA256.hash(data: name))
        chainingKey = hash
    }

    var hasKey: Bool { cipher.hasKey }

    mutating func mixHash(_ data: [UInt8]) {
        hash = Array(SHA256.hash(data: hash + data))
    }

    mutating func mixKey(_ inputKeyMaterial: [UInt8]) {
        let out = Self.hkdf(chainingKey: chainingKey, input: inputKeyMaterial, outputs: 2)
        chainingKey = out[0]
        cipher.initializeKey(SymmetricKey(data: out[1]))
    }

    mutating func mixKeyAndHash(_ inputKeyMaterial: [UInt8]) {
        let out = Self.hkdf(chainingKey: chainingKey, input: inputKeyMaterial, outputs: 3)
        chainingKey = out[0]
        mixHash(out[1])
        cipher.initializeKey(SymmetricKey(data: out[2]))
    }

    mutating func encryptAndHash(_ plaintext: [UInt8]) throws -> [UInt8] {
        let ciphertext = try cipher.encrypt(ad: hash, plaintext: plaintext)
        mixHash(ciphertext)
        return ciphertext
    }

    mutating func decryptAndHash(_ ciphertext: [UInt8]) throws -> [UInt8] {
        let plaintext = try cipher.decrypt(ad: hash, ciphertext: ciphertext)
        mixHash(ciphertext)
        return plaintext
    }

    /// Hai khoá truyền tải: (initiator → responder, responder → initiator).
    func split() -> (SymmetricKey, SymmetricKey) {
        let out = Self.hkdf(chainingKey: chainingKey, input: [], outputs: 2)
        return (SymmetricKey(data: out[0]), SymmetricKey(data: out[1]))
    }

    /// HKDF của Noise (rev 34 §4.3): HMAC-SHA256 nối tiếp với byte đếm 0x01, 0x02, 0x03.
    static func hkdf(chainingKey: [UInt8], input: [UInt8], outputs: Int) -> [[UInt8]] {
        let tempKey = SymmetricKey(data: Array(HMAC<SHA256>.authenticationCode(for: input, using: SymmetricKey(data: chainingKey))))
        var result: [[UInt8]] = []
        var previous: [UInt8] = []
        for counter in 1...outputs {
            previous = Array(HMAC<SHA256>.authenticationCode(for: previous + [UInt8(counter)], using: tempKey))
            result.append(previous)
        }
        return result
    }
}
