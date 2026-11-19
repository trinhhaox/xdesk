import SwiftUI

/// Bảng màu theo docs/brand-guide.md.
enum BrandPalette {
    static let primary = Color(red: 0x2F / 255, green: 0x6B / 255, blue: 0xFF / 255)
    /// Nền nút chính: đậm hơn `primary` một chút để chữ trắng đạt tương phản ≥ 4.5:1.
    static let primaryStrong = Color(red: 0x2A / 255, green: 0x60 / 255, blue: 0xEB / 255)
    static let accent = Color(red: 0x18 / 255, green: 0xC2 / 255, blue: 0x9C / 255)
    static let warning = Color(red: 0xF5 / 255, green: 0xA5 / 255, blue: 0x24 / 255)
}
