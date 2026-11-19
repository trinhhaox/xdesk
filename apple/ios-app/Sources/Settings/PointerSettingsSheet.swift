import SwiftUI
import XdeskInput

/// Cài đặt chuột/con trỏ: mở từ danh sách máy Mac (mục Điều khiển) hoặc thanh công cụ màn stream.
struct PointerSettingsSheet: View {
    @Bindable var store: PointerSettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
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
                        Text(speedText).monospacedDigit().frame(width: 48, alignment: .trailing)
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
            .navigationTitle("Chuột và con trỏ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Xong") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
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
