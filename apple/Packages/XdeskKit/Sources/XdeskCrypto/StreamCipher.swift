import CryptoKit

/// Mã hoá frame TCP sau bắt tay. Nonce là bộ đếm ngầm (TCP có thứ tự) bắt đầu từ 0 mỗi hướng.
/// Frame mã hoá: `u32 len | u8 kind | ciphertext | tag`, `len = 1 + plaintext + 16`;
/// AD = `u32 len BE | u8 kind` nên kind và độ dài được xác thực. Kind 0x01 không đi qua lớp này.
public enum StreamFormat {
    public static let tagLength = 16
    public static let maxFrameLength = 1_048_576

    static func associatedData(kind: UInt8, ciphertextLength: Int) -> [UInt8] {
        let len = UInt32(1 + ciphertextLength)
        return [UInt8(len >> 24), UInt8((len >> 16) & 0xFF), UInt8((len >> 8) & 0xFF), UInt8(len & 0xFF), kind]
    }
}

/// `~Copyable` vì cùng lý do với `DatagramSender`: không được có hai bản sao cùng bộ đếm nonce.
public struct StreamSender: ~Copyable, Sendable {
    private var state: NoiseCipherState

    public init(key: SymmetricKey) { state = NoiseCipherState(key: key) }

    /// Trả về `ciphertext | tag`; người gọi đóng khung `len | kind | kết quả`.
    public mutating func seal(kind: UInt8, plaintext: [UInt8]) throws -> [UInt8] {
        let ciphertextLength = plaintext.count + StreamFormat.tagLength
        guard 1 + ciphertextLength <= StreamFormat.maxFrameLength else { throw CryptoError.messageTooLarge }
        return try state.encrypt(
            ad: StreamFormat.associatedData(kind: kind, ciphertextLength: ciphertextLength), plaintext: plaintext)
    }

    /// Gọi ngay sau khi gửi frame control `rekey`; mọi frame sau dùng khoá mới và nonce 0.
    public mutating func rekey() {
        guard let key = state.key else { return }
        state.initializeKey(KeySchedule.next(key))
    }
}

public struct StreamReceiver: ~Copyable, Sendable {
    private var state: NoiseCipherState

    public init(key: SymmetricKey) { state = NoiseCipherState(key: key) }

    public mutating func open(kind: UInt8, ciphertext: [UInt8]) throws -> [UInt8] {
        guard ciphertext.count >= StreamFormat.tagLength else { throw CryptoError.messageTooShort }
        guard 1 + ciphertext.count <= StreamFormat.maxFrameLength else { throw CryptoError.messageTooLarge }
        return try state.decrypt(
            ad: StreamFormat.associatedData(kind: kind, ciphertextLength: ciphertext.count), ciphertext: ciphertext)
    }

    /// Gọi ngay sau khi giải mã xong frame control `rekey`.
    public mutating func rekey() {
        guard let key = state.key else { return }
        state.initializeKey(KeySchedule.next(key))
    }
}
