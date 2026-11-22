import Foundation

/// Khoá công khai của điện thoại dùng để ký thử thách mở khoá (viewer → host, một lần sau khi streaming).
public struct UnlockKey: Codable, Sendable, Equatable {
    public var alg: String
    public var pub: String
    public init(alg: String = UnlockAttestation.algorithm, pub: String) { self.alg = alg; self.pub = pub }
}

/// Thử thách mở khoá (host → viewer): nonce base64 32 byte, dùng một lần, hết hạn sau `ttlMs`.
public struct SystemUnlockChallenge: Codable, Sendable, Equatable {
    public var nonce: String
    public var ttlMs: UInt32
    public init(nonce: String, ttlMs: UInt32 = UnlockAttestation.challengeTTLms) { self.nonce = nonce; self.ttlMs = ttlMs }
}

/// Hằng số và định dạng dữ liệu ký cho mở khoá có chứng thực sinh trắc học.
public enum UnlockAttestation {
    public static let algorithm = "p256-ecdsa-sha256"
    public static let nonceBytes = 32
    public static let publicKeyBytes = 65
    public static let challengeTTLms: UInt32 = 30_000
    static let maxSignatureBytes = 80

    public static func decodeNonce(_ b64: String) -> [UInt8]? {
        guard let d = Data(base64Encoded: b64), d.count == nonceBytes else { return nil }
        return Array(d)
    }

    /// X9.63 uncompressed: 65 byte, bắt đầu bằng 0x04.
    public static func decodePublicKey(_ b64: String) -> [UInt8]? {
        guard let d = Data(base64Encoded: b64), d.count == publicKeyBytes, d.first == 0x04 else { return nil }
        return Array(d)
    }

    static func isPlausibleSignature(_ b64: String) -> Bool {
        guard let d = Data(base64Encoded: b64) else { return false }
        return (8...maxSignatureBytes).contains(d.count)
    }
}

/// Kết quả khoá màn hình Mac từ xa (host → viewer, không cần cap: viewer cũ bỏ qua type lạ).
public struct SystemLockResult: Codable, Sendable, Equatable {
    public var ok: Bool
    public var message: String
    public init(ok: Bool, message: String) { self.ok = ok; self.message = message }
}

/// Trạng thái màn hình Mac (host → viewer, không cần cap: viewer cũ bỏ qua type lạ). `videoAvailable:false` = Mac đang khoá hoặc
/// tắt màn hình nên chưa có hình; kênh điều khiển, input, khoá/mở khoá vẫn hoạt động. Host gửi khi viewer vào phiên và mỗi khi đổi.
public struct HostState: Codable, Sendable, Equatable {
    public var videoAvailable: Bool
    public var locked: Bool
    public init(videoAvailable: Bool, locked: Bool) { self.videoAvailable = videoAvailable; self.locked = locked }
}
