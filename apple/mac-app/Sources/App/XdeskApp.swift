import SwiftUI

@main
struct XdeskApp: App {
    private let security: SecurityCenter
    private let host: HostController
    private let viewer: ViewerController
    private let pairing: PairingCoordinator

    var body: some Scene {
        MenuBarExtra("Xdesk", systemImage: "display.2") {
            MenuBarContent(host: host, viewer: viewer, pairing: pairing)
        }
        Window("Xdesk — Kết nối tới máy khác", id: ViewerBrowserWindow.id) {
            ViewerBrowserView(controller: viewer)
        }
        .windowResizability(.contentSize)
    }

    init() {
        let security = SecurityCenter()
        let host = HostController(security: security)
        let viewer = ViewerController(security: security)
        let pairing = PairingCoordinator(security: security, host: host)
        (self.security, self.host, self.viewer, self.pairing) = (security, host, viewer, pairing)
        // Bật chia sẻ ngay khi mở app để điện thoại tìm thấy Mac mà không cần vào menu.
        Task { @MainActor in await host.start() }
        #if DEBUG
        Task { @MainActor in await AutomationHooks.run(host: host, viewer: viewer, security: security, pairing: pairing) }
        #endif
    }
}

enum ViewerBrowserWindow { static let id = "viewer-browser" }
