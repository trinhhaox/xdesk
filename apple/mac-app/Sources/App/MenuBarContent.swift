import SwiftUI
import XdeskTransport

struct MenuBarContent: View {
    let host: HostController
    let viewer: ViewerController
    let pairing: PairingCoordinator
    let agent: AgentController
    let updater: UpdaterController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusText)
        if case .listening(let port) = host.status, let ip = LocalAddress.primaryIPv4() {
            Text("Nhập trên điện thoại: \(ip):\(port)")
        }
        Toggle("Cho phép kết nối qua Tailscale", isOn: Binding(get: { host.allowTailscale }, set: { host.setAllowTailscale($0) }))
        if host.allowTailscale, case .listening(let port) = host.status, let tailscale = InterfaceFilter.tailscaleInterfaces().first {
            Text("Qua Tailscale: \(tailscale.address):\(port)")
        } else if host.allowTailscale {
            Text("Chưa thấy Tailscale trên máy này")
        }
        Toggle("Chỉ phát âm thanh trên thiết bị (tắt loa Mac)", isOn: Binding(
            get: { host.audioOptions.muteLocalOutput }, set: { host.audioOptions.setMuteLocalOutput($0) }))
        Toggle("Tự co giãn cửa sổ ứng dụng cho vừa màn hình", isOn: Binding(get: { host.fitWindows }, set: { host.setFitWindows($0) }))
        UsbMenuSection(host: host)
        if !AccessibilityPermission.isGranted {
            Button(AccessibilityPermission.menuTitle) {
                AccessibilityPermission.requestPrompt()
                AccessibilityPermission.openSettings()
            }
        }
        if host.secureInputActive {
            Text("Đang bật nhập liệu bảo mật: chữ gõ từ xa có thể không vào ô mật khẩu")
        }
        Divider()
        Button(host.isHosting ? "Dừng chia sẻ màn hình" : "Bắt đầu chia sẻ màn hình") {
            Task { host.isHosting ? await host.stop() : await host.start() }
        }
        Button("Kết nối tới máy khác…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: ViewerBrowserWindow.id)
        }
        Button("Ghép đôi thiết bị mới…") { Task { await pairing.showQrWindow() } }
        Button("Thiết bị đã ghép…") { pairing.showDevicesWindow() }
        if viewer.session != nil {
            Button("Ngắt kết nối viewer") { Task { await viewer.disconnect() } }
        }
        Divider()
        AgentMenuSection(agent: agent)
        Divider()
        if let version = updater.pendingVersion {
            Button("Có bản mới \(version) — cập nhật…") { updater.checkForUpdates() }
        }
        Button("Kiểm tra cập nhật…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
        Button("Cài đặt cập nhật…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: UpdateSettingsWindow.id)
        }
        Button("Thoát Xdesk") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusText: String {
        switch host.status {
        case .stopped: "Chưa chia sẻ"
        case .starting: "Đang khởi động…"
        case .listening(let port): host.activeViewerCount > 0 ? "Đang chia sẻ cho \(host.activeViewerCount) viewer (cổng \(port))" : "Sẵn sàng · cổng \(port)"
        case .failed(let message): "Lỗi: \(message)"
        }
    }
}
