import SwiftUI

@main
struct XdeskApp: App {
    private let host = HostController()
    private let viewer = ViewerController()

    var body: some Scene {
        MenuBarExtra("Xdesk", systemImage: "display.2") {
            MenuBarContent(host: host, viewer: viewer)
        }
        Window("Xdesk — Kết nối tới máy khác", id: ViewerBrowserWindow.id) {
            ViewerBrowserView(controller: viewer)
        }
        .windowResizability(.contentSize)
    }

    init() {
        // Bật chia sẻ ngay khi mở app để điện thoại tìm thấy Mac mà không cần vào menu.
        let host = host
        Task { @MainActor in await host.start() }
        #if DEBUG
        let viewer = viewer
        Task { @MainActor in await AutomationHooks.run(host: host, viewer: viewer) }
        #endif
    }
}

enum ViewerBrowserWindow { static let id = "viewer-browser" }
