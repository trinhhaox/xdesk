import SwiftUI
import XdeskAgent

/// Các mục cài đặt agent (nằm trong Form của tab Agent AI): thời gian im lặng trước khi tự nhả quyền và luật theo app (allow/ask/never).
struct AgentSettingsView: View {
    @Bindable var settings: AgentSettings
    @State private var newBundleId = ""
    @State private var newRule: AppRule = .never

    var body: some View {
        Group {
            Section("Quyền điều khiển") {
                Stepper("Tự nhả quyền sau \(settings.idleSeconds) giây im lặng", value: $settings.idleSeconds, in: AgentSettings.idleRange, step: 15)
                Text("Dừng nhanh bằng \(StopHotkey.label). Chạm chuột/bàn phím vào màn hình agent cũng tự tạm dừng.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Luật theo ứng dụng (app chưa có luật: hỏi)") {
                ForEach(settings.policy.rules.keys.sorted(), id: \.self) { id in
                    HStack {
                        Text(id).textSelection(.enabled)
                        Spacer()
                        Picker("", selection: ruleBinding(id)) {
                            ForEach(AppRule.allCases, id: \.self) { Text(label($0)).tag($0) }
                        }.labelsHidden().frame(width: 110)
                        Button("Xoá", role: .destructive) { settings.policy.rules[id] = nil }
                    }
                }
                HStack {
                    TextField("Bundle id, ví dụ com.apple.TextEdit", text: $newBundleId)
                    Picker("", selection: $newRule) { ForEach(AppRule.allCases, id: \.self) { Text(label($0)).tag($0) } }.labelsHidden().frame(width: 110)
                    Button("Thêm") {
                        let id = newBundleId.trimmingCharacters(in: .whitespaces)
                        guard !id.isEmpty else { return }
                        settings.policy.rules[id] = newRule
                        newBundleId = ""
                    }
                }
            }
        }
    }

    private func ruleBinding(_ id: String) -> Binding<AppRule> {
        Binding(get: { settings.policy.rules[id] ?? .ask }, set: { settings.policy.rules[id] = $0 })
    }

    private func label(_ rule: AppRule) -> String {
        switch rule {
        case .allow: String(localized: "Cho phép")
        case .ask: String(localized: "Hỏi")
        case .never: String(localized: "Cấm")
        }
    }
}
