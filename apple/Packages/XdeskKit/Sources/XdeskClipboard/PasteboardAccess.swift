import Foundation

/// Truy cập clipboard hệ thống (hoặc bản giả trong test). Triển khai phải an toàn khi gọi từ nhiều luồng.
public protocol PasteboardAccess: Sendable {
    /// Tăng mỗi khi nội dung đổi (kể cả do chính ta ghi).
    var changeCount: Int { get }
    /// Mục hiện tại; nil nếu rỗng, nhạy cảm (`ClipboardPolicy`), quá lớn hoặc không hỗ trợ.
    func read() -> ClipboardItem?
    /// Ghi `item` thay nội dung cũ; trả `changeCount` ngay sau khi ghi (để bỏ qua thay đổi do chính ta gây ra).
    func write(_ item: ClipboardItem) -> Int
}
