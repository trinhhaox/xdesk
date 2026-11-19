import Foundation

/// Quy ước nspasteboard.org: trình quản lý mật khẩu (1Password, Bitwarden…) đánh dấu mục nhạy cảm/tạm thời bằng các type này.
public enum ClipboardPolicy {
    public static let sensitiveTypes: Set<String> = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"]

    /// Lý do không được đọc clipboard, hoặc nil nếu đọc được.
    public static func refusalReason(types: [String]) -> String? {
        guard types.contains(where: sensitiveTypes.contains) else { return nil }
        return "clipboard chứa mục ẩn (mật khẩu/mã tạm) theo quy ước nspasteboard.org nên không đọc"
    }
}
