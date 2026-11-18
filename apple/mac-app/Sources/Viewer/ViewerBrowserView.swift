import SwiftUI
import XdeskTransport
import XdeskViewer

/// Cửa sổ chọn host: danh sách Bonjour + nhập tay `host:port`.
struct ViewerBrowserView: View {
    @Bindable var controller: ViewerController
    @State private var manualText = ""

    var body: some View {
        Form {
            Section("Máy tìm thấy trên mạng") {
                if controller.hosts.isEmpty {
                    Text("Đang tìm… (host cần bật \"Bắt đầu chia sẻ\")").foregroundStyle(.secondary)
                }
                ForEach(controller.hosts) { host in
                    Button { connect(.discovered(host), title: host.name) } label: {
                        Label(host.name, systemImage: "desktopcomputer")
                    }
                    .disabled(controller.isConnecting)
                }
            }
            Section("Nhập địa chỉ") {
                TextField("host:port, ví dụ 127.0.0.1:47800", text: $manualText)
                    .onSubmit(connectManual)
                Button("Kết nối", action: connectManual)
                    .disabled(ViewerTarget.parse(manual: manualText) == nil || controller.isConnecting)
            }
            Section("Tuỳ chọn") {
                Toggle("Retina (HiDPI 2×, 3840×2400)", isOn: $controller.options.retina)
                Toggle("Mở toàn màn hình", isOn: $controller.options.fullScreen)
            }
            if controller.isConnecting { ProgressView("Đang kết nối…") }
            if let message = controller.errorMessage { Text(message).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 420)
        .onAppear { controller.startBrowsing() }
        .onDisappear { controller.stopBrowsing() }
    }

    private func connectManual() {
        guard let target = ViewerTarget.parse(manual: manualText) else { return }
        connect(target, title: manualText)
    }

    private func connect(_ target: ViewerTarget, title: String) {
        Task { await controller.connect(to: target, title: title) }
    }
}
