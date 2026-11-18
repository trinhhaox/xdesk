import CryptoKit
import Foundation

/// Mã so khớp 6 số (SAS) cho ghép đôi `XX`, có cam kết chống MITM mài khoá. Thiết kế: `crypto-handshake.md` §SAS.
public enum ShortAuthString {
    public static let nonceLength = 16
    public static let commitmentLength = 32
    private static let commitLabel = Array("xdesk v1 sas-commit".utf8)
    private static let codeLabel = Array("xdesk v1 sas".utf8)

    public static func randomNonce() -> [UInt8] {
        (0..<nonceLength).map { _ in UInt8.random(in: 0...255) }
    }

    /// `SHA-256("xdesk v1 sas-commit" | e.pub | s.pub | nonce)` của initiator, gửi trước message 1.
    public static func commitment(ephemeralKey: [UInt8], staticKey: [UInt8], nonce: [UInt8]) throws -> [UInt8] {
        guard ephemeralKey.count == 32, staticKey.count == 32, nonce.count == nonceLength else {
            throw CryptoError.invalidLength
        }
        return Array(SHA256.hash(data: commitLabel + ephemeralKey + staticKey + nonce))
    }

    /// Responder kiểm sau message 3 (khi đã biết e, s, nonce của initiator); so sánh thời gian hằng.
    public static func verify(
        commitment: [UInt8], ephemeralKey: [UInt8], staticKey: [UInt8], nonce: [UInt8]
    ) throws -> Bool {
        ConstantTime.equals(commitment, try self.commitment(ephemeralKey: ephemeralKey, staticKey: staticKey, nonce: nonce))
    }

    /// Mã 0…999 999: `u64 BE(HKDF-SHA256(ikm: nonce, salt: messageTwoHash, info: "xdesk v1 sas", 8 B)) mod 10^6`.
    /// `messageTwoHash` là handshake hash ngay sau message 2 (`NoiseHandshakeState.messageTwoHash`), KHÔNG phải hash sau
    /// message 3: payload message 3 do initiator (có thể là kẻ MITM) chọn tự do nên không được ảnh hưởng mã.
    public static func code(messageTwoHash: [UInt8], nonce: [UInt8]) throws -> UInt32 {
        guard messageTwoHash.count == 32, nonce.count == nonceLength else { throw CryptoError.invalidLength }
        let bytes = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: nonce), salt: messageTwoHash, info: codeLabel, outputByteCount: 8
        ).bytes
        let value = bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return UInt32(value % 1_000_000)
    }

    /// Hiển thị "123 456" (đủ 6 chữ số, thêm số 0 đứng đầu).
    public static func format(_ code: UInt32) -> String {
        let text = String(format: "%06u", code % 1_000_000)
        return "\(text.prefix(3)) \(text.suffix(3))"
    }
}
