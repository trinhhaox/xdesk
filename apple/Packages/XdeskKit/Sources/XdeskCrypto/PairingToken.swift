import CryptoKit
import Foundation

/// Không `Equatable` có chủ đích: `==` không hằng thời gian sẽ mời so sánh token bằng đường sai. Dùng `PairingTokenIssuer.consume`.
public struct PairingToken: Sendable, Redacted {
    public static let length = 32
    /// Token QR chỉ hợp lệ 2 phút.
    public static let lifetime: TimeInterval = 120

    public let bytes: [UInt8]
    public let expiresAt: Date
}

/// Token ghép đôi của host: một token hoạt động tại một thời điểm, dùng một lần, hết hạn sau 2 phút.
/// Token là psk của `XXpsk3`; host dùng `activeToken` để bắt tay rồi `consume` khi bắt tay thành công.
/// `~Copyable`: bản sao sẽ làm "dùng một lần" chỉ đúng trên từng bản.
public struct PairingTokenIssuer: ~Copyable, Sendable {
    public static let maxFailures = 5

    private var active: PairingToken?
    private var failures = 0

    // Deinit tường minh: huỷ qua hàm của XdeskCrypto, không để module khác inline việc huỷ các kiểu nội bộ (lỗi liên kết Release).
    deinit {}

    public init() {}

    /// Phát token mới (vô hiệu token cũ). `bytes` chỉ để test xác định; mặc định lấy từ RNG hệ thống.
    @discardableResult
    public mutating func issue(
        now: Date = Date(), bytes: [UInt8]? = nil
    ) throws -> PairingToken {
        let bytes = bytes ?? SymmetricKey(size: .bits256).bytes
        guard bytes.count == PairingToken.length else { throw CryptoError.invalidLength }
        let token = PairingToken(bytes: bytes, expiresAt: now.addingTimeInterval(PairingToken.lifetime))
        active = token
        failures = 0
        return token
    }

    public func activeToken(now: Date = Date()) -> PairingToken? {
        guard let active, now < active.expiresAt else { return nil }
        return active
    }

    /// Đánh dấu đã dùng nếu `candidate` đúng token đang hiệu lực (so sánh thời gian hằng). Trả `false` nếu sai/hết hạn/đã dùng.
    public mutating func consume(matching candidate: [UInt8], now: Date = Date()) -> Bool {
        guard let token = activeToken(now: now), ConstantTime.equals(token.bytes, candidate) else { return false }
        active = nil
        return true
    }

    /// Ghi một lần bắt tay hỏng; đủ `maxFailures` lần thì vô hiệu token. Trả `true` nếu token vừa bị vô hiệu.
    @discardableResult
    public mutating func recordFailure() -> Bool {
        guard active != nil else { return false }
        failures += 1
        guard failures >= Self.maxFailures else { return false }
        active = nil
        return true
    }

    /// Vô hiệu token đang hiệu lực (vd. có phiên đang chạy, hoặc người dùng đóng cửa sổ QR).
    public mutating func invalidate() { active = nil }
}
