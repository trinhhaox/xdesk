import SwiftUI
import XdeskViewer
import XdeskWire

/// Màn Cài đặt (mở từ nút bánh răng trên thanh công cụ): chế độ hiển thị, kiểu bản sao, bộ mã hoá, giao diện, chuột và bảo mật.
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
            Section {
                Picker("Bộ mã hoá", selection: $model.videoCodec) {
                    Text("HEVC (H.265)").tag(VideoCodec.hevc)
                    Text("H.264").tag(VideoCodec.h264)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Bộ mã hoá video")
            } footer: {
                Text(model.videoCodec == .hevc
                     ? "HEVC nén tốt hơn ~40%, giảm độ trễ trên Wi-Fi/Tailscale và tiết kiệm pin."
                     : "H.264 tương thích rộng nhất với mọi thiết bị.")
            }
            AppearancePicker()
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
        .scrollContentBackground(.hidden)
        .background(BrandPalette.background)
        .navigationTitle("Cài đặt")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refreshTrust() }
    }
}
