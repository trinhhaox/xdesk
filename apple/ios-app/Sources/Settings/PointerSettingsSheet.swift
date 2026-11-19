import SwiftUI
import XdeskInput

/// Sheet cài đặt chuột trên màn stream (menu nút nổi); màn Cài đặt dùng thẳng `PointerSettingsForm`.
struct PointerSettingsSheet: View {
    @Bindable var store: PointerSettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PointerSettingsForm(store: store)
                .toolbar { Button("Xong") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Nội dung cài đặt chuột/con trỏ (không kèm NavigationStack để đẩy vào màn Cài đặt hoặc bọc trong sheet).
struct PointerSettingsForm: View {
    @Bindable var store: PointerSettingsStore

    var body: some View {
            Form {
                Section {
                    Picker("Chế độ", selection: $store.settings.mode) {
                        ForEach(PointerMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(modeHelp).font(.footnote).foregroundStyle(.secondary)
                }
                Section("Tốc độ con trỏ") {
                    HStack {
                        Slider(value: speedBinding, in: PointerSettings.speedRange, step: 0.1)
                            .accessibilityLabel("Tốc độ con trỏ")
                            .accessibilityValue(speedText)
                        Text(speedText).monospacedDigit().frame(minWidth: 48, alignment: .trailing)
                    }
                    .disabled(store.settings.mode != .trackpad)
                    if store.settings.mode != .trackpad {
                        Text("Chỉ dùng ở chế độ Con trỏ.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Toggle("Cuộn tự nhiên", isOn: $store.settings.naturalScroll)
                    Toggle("Nhấn giữ để chuột phải", isOn: $store.settings.longPressRightClick)
                } footer: {
                    Text("Cuộn tự nhiên: nội dung đi theo ngón tay. Hai ngón chạm cùng lúc luôn là chuột phải.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(BrandPalette.background)
            .navigationTitle("Chuột và con trỏ")
            .navigationBarTitleDisplayMode(.inline)
    }

    private var modeHelp: String {
        switch store.settings.mode {
        case .direct: "Chạm đâu click đó. Kéo một ngón để kéo thả, hai ngón để cuộn, nhấn giữ để chuột phải."
        case .trackpad: "Trượt một ngón để di chuyển con trỏ, chạm để click. Hai ngón chạm = chuột phải, hai ngón trượt = cuộn, chạm rồi chạm-giữ-trượt = kéo."
        }
    }

    private var speedText: String { String(format: "%.1f×", store.settings.speed) }

    private var speedBinding: Binding<Float> {
        Binding(get: { store.settings.speed }, set: { store.settings.speed = $0 })
    }
}
