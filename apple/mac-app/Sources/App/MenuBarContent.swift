import SwiftUI

struct MenuBarContent: View {
    let host: HostController
    let viewer: ViewerController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusText)
        Divider()
        Button(host.isHosting ? "Dừng chia sẻ màn hình" : "Bắt đầu chia sẻ màn hình") {
            Task { host.isHosting ? await host.stop() : await host.start() }
        }
        Button("Kết nối tới máy khác…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: ViewerBrowserWindow.id)
        }
        if viewer.session != nil {
            Button("Ngắt kết nối viewer") { Task { await viewer.disconnect() } }
        }
        Divider()
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
