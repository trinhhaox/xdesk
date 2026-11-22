import Foundation

/// Khoá ký gắn với xác thực sinh trắc học của điện thoại (iOS: Secure Enclave `.userPresence`).
/// Giữ giao diện nhỏ để phần còn lại của luồng mở khoá kiểm thử được không cần phần cứng.
public protocol UnlockSigner: Sendable {
    /// Khoá công khai X9.63 (65 byte); tạo khoá nếu chưa có (không cần xác thực người dùng).
    func publicKey() async throws -> [UInt8]
    /// Khoá công khai đã có (không tạo mới); `nil` nếu chưa có. Dùng để hiện dấu vân tay trong Cài đặt.
    func existingPublicKey() async -> [UInt8]?
    /// Ký ECDSA-SHA256 (DER) lên `message`, CHỈ tra khoá đã có (không tạo). Việc ký tự kích hoạt Face ID / mật mã, lời nhắc nêu tên `hostName`;
    /// ném `UnlockSigningError.cancelled` nếu người dùng huỷ, `.unavailable` nếu chưa có khoá.
    func sign(message: [UInt8], hostName: String) async throws -> [UInt8]
}

public enum UnlockSigningError: Error, Sendable, Equatable {
    case cancelled
    case unavailable
}

/// Chỉ ký khi người dùng vừa bấm "Mở khoá Mac": cờ hết hạn sau 30 s hoặc sau đúng một thử thách; thử thách không mời bị bỏ.
struct UnlockRequestGate: Sendable {
    static let window: TimeInterval = 30
    private var armedUntil: Date?

    mutating func arm(now: Date = Date()) { armedUntil = now.addingTimeInterval(Self.window) }

    /// `true` đúng một lần cho mỗi lần `arm` còn hạn.
    mutating func consume(now: Date = Date()) -> Bool {
        defer { armedUntil = nil }
        guard let until = armedUntil else { return false }
        return now <= until
    }

    mutating func reset() { armedUntil = nil }
}
