import SwiftUI
import UIKit

/// Màu thương hiệu theo docs/brand-guide.md và docs/design-tokens.md (cùng giá trị với XdeskTheme.kt bên Android), dùng như token ngữ nghĩa. Màu chữ/biểu tượng có biến thể sáng/tối riêng để đạt tương phản
/// ≥ 4.5:1 trên nền #F6F7FA (sáng) và #101218 (tối); `primaryFill` giữ nguyên #2F6BFF của brand cho nền nút/phím (chữ trắng trên đó).
enum BrandPalette {
    /// Màu nhấn/tint toàn app (chữ, liên kết, viền). Sáng: #2457E6, tối: #5B8CFF.
    static let primary = dynamic(light: 0x2457E6, dark: 0x5B8CFF)
    /// Nền đặc brand #2F6BFF cho phím đang khoá, nút nổi bật (chữ trắng).
    static let primaryFill = Color(hex: 0x2F6BFF)
    /// Trạng thái tốt ("Đã ghép"). Sáng: #0B7A63, tối: #18C29C.
    static let accent = dynamic(light: 0x0B7A63, dark: 0x18C29C)
    /// Cảnh báo ("Chưa ghép"). Sáng: #8A5A00, tối: #F5A524.
    static let warning = dynamic(light: 0x8A5A00, dark: 0xF5A524)
    /// Lỗi. Sáng: #C62828, tối: #FF6B6B.
    static let danger = dynamic(light: 0xC62828, dark: 0xFF6B6B)
    /// Nền màn hình: sáng #F6F7FA, tối #101218.
    static let background = dynamic(light: 0xF6F7FA, dark: 0x101218)
    /// Nền tối cố định #101218 cho lớp phủ trên video (không đổi theo giao diện).
    static let overlaySurface = Color(hex: 0x101218)
    /// Thẻ và thanh phụ trên nền tối cố định (khớp `XdeskOverlay.bar`).
    static let overlayCard = Color(hex: 0x1C1C1E)
    /// Nút phím và ô chạm trên lớp phủ tối cố định (khớp `XdeskOverlay.key`).
    static let overlayKey = Color(hex: 0x2C2C2E)
    /// Màu nhấn trên lớp phủ tối cố định (tương phản ≥ 4.5:1 trên #101218).
    static let primaryOnOverlay = Color(hex: 0x5B8CFF)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

private extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}
