import AppKit
import ApplicationServices

/// Quyền Trợ năng (Accessibility): bắt buộc để `CGEventPost` có tác dụng. Không thể tự cấp: chỉ kiểm tra, hiện hộp thoại và mở đúng trang cài đặt.
enum AccessibilityPermission {
    static let menuTitle = String(localized: "Cần quyền Trợ năng để điều khiển")
    static let guidance = String(localized: "Để điều khiển Mac từ thiết bị khác: Cài đặt hệ thống › Quyền riêng tư & Bảo mật › Trợ năng › bật Xdesk.")
    private static let settingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Hiện hộp thoại hệ thống (đồng thời thêm app vào danh sách). Trả trạng thái hiện tại.
    @discardableResult
    static func requestPrompt() -> Bool {
        // Hằng `kAXTrustedCheckOptionPrompt` là biến toàn cục không an toàn đồng thời trong Swift 6; khoá chuỗi của nó là cố định.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openSettings() {
        guard let url = URL(string: settingsURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
