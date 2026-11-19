import SwiftUI
import XdeskViewer
import XdeskWire

/// Màn Cài đặt (đẩy từ nút bánh răng hoặc dòng tóm tắt ở danh sách): chế độ hiển thị, kiểu bản sao, chuột và bảo mật.
struct SettingsView: View {
    let model: StreamViewModel
    let pointer: PointerSettingsStore

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Chế độ", selection: $model.screenMode) {
                    Text("Bản sao").tag(ScreenMode.mirror)
                    Text("Mở rộng").tag(ScreenMode.extend)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Chế độ hiển thị")
            } footer: {
                Text(model.screenMode == .extend
                     ? "Điện thoại là màn hình thứ hai bên phải Mac. Kéo cửa sổ sang để dùng."
                     : "Điện thoại hiện đúng màn hình Mac. Chọn bên dưới Mac giữ nguyên hay đổi theo điện thoại.")
            }
            if model.screenMode == .mirror { MirrorFitPicker(fit: $model.mirrorFit, pointer: pointer) }
            Section("Điều khiển") {
                NavigationLink {
                    PointerSettingsForm(store: pointer)
                } label: {
                    LabeledContent("Chuột và con trỏ", value: pointer.settings.mode.title)
                }
            }
            Section("Bảo mật") {
                NavigationLink {
                    SecuritySettingsView(model: model)
                } label: {
                    LabeledContent("Thiết bị và máy đã ghép", value: "\(model.knownHosts.count) máy")
                }
            }
        }
        .navigationTitle("Cài đặt")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refreshTrust() }
    }
}

/// Dòng tóm tắt một dòng ở danh sách máy, ví dụ "Bản sao · Vừa với điện thoại · Chạm trực tiếp"; chạm để mở Cài đặt.
struct SettingsSummaryRow: View {
    let model: StreamViewModel
    let pointer: PointerSettingsStore

    var body: some View {
        NavigationLink {
            SettingsView(model: model, pointer: pointer)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cài đặt")
                    Text(summary).font(.subheadline).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "gearshape")
            }
        }
        .accessibilityHint("Mở cài đặt chế độ hiển thị, chuột và bảo mật")
    }

    private var summary: String {
        let parts = model.screenMode == .mirror
            ? ["Bản sao", model.mirrorFit.title, pointer.settings.mode.title]
            : ["Mở rộng", pointer.settings.mode.title]
        return parts.joined(separator: " · ")
    }
}
