import CryptoKit

/// Phía gửi UDP: mã hoá từng gói media, header rõ làm AD. Không thread-safe; chủ sở hữu tự đồng bộ.
/// `~Copyable`: bản sao giữ cùng khoá + bộ đếm sẽ tái dùng nonce (phá ChaCha20-Poly1305). Gửi lại theo NACK phải gọi `seal` trên chủ duy nhất.
public struct DatagramSender: ~Copyable, Sendable {
    private var key: SymmetricKey
    public private(set) var epoch: UInt32 = 0
    public private(set) var packetsInEpoch: UInt64 = 0
    private var epochStart: ContinuousClock.Instant

    // Deinit tường minh: huỷ qua hàm của XdeskCrypto, không để module khác inline việc huỷ các kiểu nội bộ (lỗi liên kết Release).
    deinit {}

    public init(key: SymmetricKey, now: ContinuousClock.Instant = .now) {
        self.key = key
        epochStart = now
    }

    public var needsRekey: Bool { needsRekey(now: .now) }

    /// `true` khi đã gửi gần 2^32 gói hoặc epoch sống ≥ 1 giờ.
    public func needsRekey(now: ContinuousClock.Instant) -> Bool {
        packetsInEpoch >= DatagramFormat.rekeyPacketThreshold || now - epochStart >= DatagramFormat.rekeyInterval
    }

    /// Chuyển sang epoch kế tiếp (khoá mới, counter về 0). Bên nhận tự theo kịp khi gói đầu của epoch mới xác thực được.
    public mutating func rekey(now: ContinuousClock.Instant = .now) throws {
        guard epoch != UInt32.max else { throw CryptoError.nonceExhausted }
        key = KeySchedule.next(key)
        epoch += 1
        packetsInEpoch = 0
        epochStart = now
    }

    /// Trả về `header | nonce | ciphertext | tag`. `header` phải đúng 16 byte.
    public mutating func seal(header: [UInt8], payload: [UInt8]) throws -> [UInt8] {
        guard header.count == DatagramFormat.headerLength else { throw CryptoError.invalidLength }
        guard packetsInEpoch < DatagramFormat.packetsPerEpoch else { throw CryptoError.nonceExhausted }
        let nonce = UInt64(epoch) << 32 | packetsInEpoch
        let box = try ChaChaPoly.seal(payload, using: key, nonce: ChaChaNonce.make(counter: nonce), authenticating: header)
        packetsInEpoch += 1
        return header + (0..<8).map { UInt8(truncatingIfNeeded: nonce >> (56 - 8 * UInt64($0))) }
            + Array(box.ciphertext) + Array(box.tag)
    }
}
