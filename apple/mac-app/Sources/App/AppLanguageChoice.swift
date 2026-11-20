import Foundation

/// Lựa chọn ngôn ngữ giao diện trong Cài đặt, ánh xạ với khoá `AppleLanguages` của ứng dụng.
/// Không có khoá (`nil`) nghĩa là theo ngôn ngữ hệ thống.
enum AppLanguageChoice: String, CaseIterable, Identifiable, Sendable {
    case system, vietnamese, english

    static let defaultsKey = "AppleLanguages"

    var id: String { rawValue }

    /// Giá trị ghi vào `AppleLanguages`; `nil` = xoá khoá để theo hệ thống.
    var appleLanguages: [String]? {
        switch self {
        case .system: nil
        case .vietnamese: ["vi"]
        case .english: ["en"]
        }
    }

    /// Suy ra lựa chọn từ giá trị `AppleLanguages` đã lưu cho app; mã lạ hoặc rỗng coi như theo hệ thống.
    init(appleLanguages: [String]?) {
        let first = appleLanguages?.first?.lowercased() ?? ""
        if first == "vi" || first.hasPrefix("vi-") { self = .vietnamese }
        else if first == "en" || first.hasPrefix("en-") { self = .english }
        else { self = .system }
    }

    /// Đọc lựa chọn đã lưu riêng cho app (bỏ qua ngôn ngữ hệ thống, vì `array(forKey:)` trả cả giá trị toàn cục).
    static func stored(in defaults: UserDefaults = .standard, bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> AppLanguageChoice {
        guard let bundleIdentifier, let domain = defaults.persistentDomain(forName: bundleIdentifier) else { return .system }
        return AppLanguageChoice(appleLanguages: domain[defaultsKey] as? [String])
    }

    func save(to defaults: UserDefaults = .standard) {
        if let languages = appleLanguages {
            defaults.set(languages, forKey: Self.defaultsKey)
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
    }
}
