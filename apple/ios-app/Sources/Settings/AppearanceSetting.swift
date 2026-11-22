import SwiftUI

/// Giao diện app: mặc định Tối; `.system` ("Theo hệ thống") không ép màu (`preferredColorScheme(nil)`). Lưu ở `UserDefaults` khoá `xdesk.appearance`.
enum AppearanceSetting: String, CaseIterable, Sendable {
    case dark, light, system

    static let storageKey = "xdesk.appearance"

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }

    var title: String {
        switch self {
        case .dark: "Tối"
        case .light: "Sáng"
        case .system: "Theo hệ thống"
        }
    }

    var summary: String {
        switch self {
        case .dark: "Nền tối, dịu mắt. Mặc định."
        case .light: "Nền sáng."
        case .system: "Đổi theo cài đặt Sáng/Tối của điện thoại."
        }
    }

    var symbol: String {
        switch self {
        case .dark: "moon.fill"
        case .light: "sun.max"
        case .system: "circle.lefthalf.filled"
        }
    }
}

/// Mục "Giao diện" ở màn Cài đặt: Tối (mặc định) | Sáng | Theo hệ thống, áp dụng ngay (cùng kiểu danh sách chọn với "Kiểu bản sao").
struct AppearancePicker: View {
    @AppStorage(AppearanceSetting.storageKey) private var raw = AppearanceSetting.dark.rawValue

    var body: some View {
        Section("Giao diện") {
            ForEach(AppearanceSetting.allCases, id: \.rawValue) { option in
                let selected = raw == option.rawValue
                Button {
                    Haptics.light()
                    raw = option.rawValue
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: option.symbol)
                            .font(.title3)
                            .foregroundStyle(BrandPalette.primary)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                                .foregroundStyle(.primary)
                            Text(option.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(BrandPalette.primary)
                        }
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
