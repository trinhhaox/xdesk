import CoreGraphics

/// Quyền Screen Recording (macOS 15+ hỏi lại định kỳ). Không thể tự cấp: chỉ kiểm tra và kích hoạt hộp thoại.
enum PermissionsCheck {
    static let settingsHint = String(localized: "Cài đặt hệ thống › Quyền riêng tư & Bảo mật › Ghi màn hình và âm thanh hệ thống › bật Xdesk")

    static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    /// Hiện hộp thoại hệ thống lần đầu (đồng thời đăng ký app vào danh sách). Trả trạng thái hiện tại.
    @discardableResult
    static func requestScreenRecording() -> Bool { CGRequestScreenCaptureAccess() }
}
