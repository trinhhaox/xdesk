/// Bố cục gói UDP mã hoá: `header 16 B (rõ, là AD) | nonce u64 BE (8 B) | ciphertext | tag 16 B`.
/// Nonce = `epoch u32 << 32 | counter u32`; nonce ChaCha 12 B = 4 byte 0 | nonce u64 little-endian.
public enum DatagramFormat {
    public static let headerLength = 16
    public static let nonceLength = 8
    public static let tagLength = 16
    /// Byte thêm vào mỗi gói so với gói rõ: nonce + tag.
    public static let overhead = nonceLength + tagLength
    /// Số gói tối đa mỗi epoch (counter 32 bit); `seal` từ chối khi hết.
    public static let packetsPerEpoch: UInt64 = 1 << 32
    /// `needsRekey` bật sớm hơn giới hạn cứng một đoạn đệm cho các gói đang bay.
    public static let rekeyPacketThreshold: UInt64 = packetsPerEpoch - 65_536
    public static let rekeyInterval: Duration = .seconds(3600)
}
