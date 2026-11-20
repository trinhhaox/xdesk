import Foundation

/// Quy tắc thuần cho màn Cập nhật (tách khỏi Sparkle để test).
enum UpdateReminderPolicy {
    /// `true` = để hộp thoại chuẩn của Sparkle hiện ngay (app đang ở tiêu điểm, ví dụ vừa mở);
    /// `false` = app tự nhắc nhẹ qua menu để không chen vào việc của người dùng.
    static func sparkleShouldPresent(inImmediateFocus immediateFocus: Bool) -> Bool { immediateFocus }
}

enum UpdateSettingsText {
    static func versionLine(shortVersion: String?, build: String?) -> String {
        String(localized: "Phiên bản \(shortVersion ?? "?") (bản dựng \(build ?? "?"))")
    }

    static func lastCheckLine(_ date: Date?, now: Date = .now, locale: Locale = .autoupdatingCurrent) -> String {
        guard let date else { return String(localized: "Chưa kiểm tra lần nào") }
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)
        let formatted = date > now ? now.formatted(style) : date.formatted(style)
        return String(localized: "Lần kiểm tra gần nhất: \(formatted)")
    }
}
