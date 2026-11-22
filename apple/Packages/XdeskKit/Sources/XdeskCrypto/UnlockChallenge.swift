import CryptoKit
import Foundation

/// Định dạng khoá/chữ ký của khoá sinh trắc học mở khoá (P-256, ECDSA-SHA256, chữ ký DER X9.62).
public enum UnlockKeyFormat {
    public static let publicKeyBytes = 65
    private static let domain = Array("xdesk v1 unlock".utf8)

    /// Dữ liệu được ký: `"xdesk v1 unlock" || hostStaticPub(32) || viewerStaticPub(32) || nonce`.
    /// Gắn khoá tĩnh Noise của hai đầu để chữ ký không dùng lại được ở cặp host/viewer khác.
    public static func signedMessage(hostKey: [UInt8], viewerKey: [UInt8], nonce: [UInt8]) -> [UInt8] {
        domain + hostKey + viewerKey + nonce
    }

    /// Dấu vân tay ngắn để người dùng đối chiếu giữa Mac và điện thoại: 8 byte đầu của SHA-256, `XXXX-XXXX-XXXX-XXXX`.
    public static func fingerprint(of key: [UInt8]) -> String {
        let hex = SHA256.hash(data: key).prefix(8).map { String(format: "%02X", $0) }.joined()
        return stride(from: 0, to: hex.count, by: 4).map { i in
            let start = hex.index(hex.startIndex, offsetBy: i)
            return String(hex[start..<hex.index(start, offsetBy: 4)])
        }.joined(separator: "-")
    }

    /// Khoá X9.63 uncompressed hợp lệ (đúng độ dài và nằm trên đường cong).
    public static func isValid(_ key: [UInt8]) -> Bool {
        key.count == publicKeyBytes && key.first == 0x04 && (try? P256.Signing.PublicKey(x963Representation: key)) != nil
    }

    /// `false` nếu khoá/chữ ký sai định dạng hoặc chữ ký không khớp (không bao giờ ném).
    public static func verify(publicKey: [UInt8], message: [UInt8], derSignature: [UInt8]) -> Bool {
        guard let key = try? P256.Signing.PublicKey(x963Representation: publicKey),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: derSignature)
        else { return false }
        return key.isValidSignature(signature, for: SHA256.hash(data: message))
    }
}

/// Nonce thử thách của MỘT phiên host: một nonce đang chờ, dùng một lần, hết hạn theo TTL.
public struct UnlockChallengeBook: Sendable {
    public enum Failure: Error, Sendable, Equatable {
        case noChallenge
        case expired
        case badSignature
    }

    private var pending: (nonce: [UInt8], expires: Date)?
    private let ttl: TimeInterval

    public init(ttl: TimeInterval = 30) { self.ttl = ttl }

    /// Phát nonce 32 byte mới; nonce đang chờ (nếu có) bị thay thế.
    public mutating func issue(now: Date = Date()) -> [UInt8] {
        var nonce = [UInt8](repeating: 0, count: 32)
        for i in nonce.indices { nonce[i] = UInt8.random(in: .min ... .max) }
        pending = (nonce, now.addingTimeInterval(ttl))
        return nonce
    }

    /// Huỷ nonce đang chờ (khi lần thử bị từ chối trước khi xác minh).
    public mutating func discard() { pending = nil }

    /// Xác minh chữ ký trên nonce đang chờ; `nil` = hợp lệ. Nonce bị tiêu thụ ở MỌI lần thử (đúng hay sai) nên không dùng lại được.
    public mutating func consume(
        publicKey: [UInt8], hostKey: [UInt8], viewerKey: [UInt8], derSignature: [UInt8], now: Date = Date()
    ) -> Failure? {
        guard let current = pending else { return .noChallenge }
        pending = nil
        guard now <= current.expires else { return .expired }
        let ok = UnlockKeyFormat.verify(
            publicKey: publicKey, message: UnlockKeyFormat.signedMessage(hostKey: hostKey, viewerKey: viewerKey, nonce: current.nonce),
            derSignature: derSignature)
        return ok ? nil : .badSignature
    }
}
