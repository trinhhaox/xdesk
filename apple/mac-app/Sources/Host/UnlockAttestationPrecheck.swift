import Foundation

/// Điều kiện bắt buộc trước khi Mac phát thử thách hoặc gõ mật khẩu: viewer phải hỗ trợ chứng thực và đã đăng ký khoá (Fail-Closed).
enum UnlockAttestationPrecheck: Equatable {
    case ok
    case viewerNeedsUpdate
    case keyNotEnrolled

    static func evaluate(attestationNegotiated: Bool, storedKey: [UInt8]?) -> UnlockAttestationPrecheck {
        guard attestationNegotiated else { return .viewerNeedsUpdate }
        guard storedKey != nil else { return .keyNotEnrolled }
        return .ok
    }

    var message: String? {
        switch self {
        case .ok: nil
        case .viewerNeedsUpdate: "Cập nhật app Xdesk trên điện thoại để mở khoá bằng Face ID"
        case .keyNotEnrolled: "Chưa đăng ký khoá — bấm Đặt lại khoá (Cài đặt Xdesk › Thiết bị trên Mac) rồi mở khoá từ điện thoại trong 5 phút"
        }
    }
}
