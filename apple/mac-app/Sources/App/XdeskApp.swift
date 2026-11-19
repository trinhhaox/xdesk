import SwiftUI

@main
struct XdeskApp: App {
    private let security: SecurityCenter
    private let host: HostController
    private let viewer: ViewerController
    private let pairing: PairingCoordinator
    private let agent: AgentController
    private let updater: UpdaterController

    var body: some Scene {
        MenuBarExtra("Xdesk", systemImage: "display.2") {
            MenuBarContent(host: host, viewer: viewer, pairing: pairing, agent: agent, updater: updater)
        }
        Window("Xdesk — Kết nối tới máy khác", id: ViewerBrowserWindow.id) {
            ViewerBrowserView(controller: viewer)
        }
        .windowResizability(.contentSize)
        Window("Xdesk — Cài đặt agent AI", id: AgentSettingsWindow.id) {
            AgentSettingsView(settings: agent.settings)
        }
        .windowResizability(.contentSize)
    }

    init() {
        let security = SecurityCenter()
        let host = HostController(security: security)
        let viewer = ViewerController(security: security)
        let pairing = PairingCoordinator(security: security, host: host)
        let agent = AgentController(host: host)
        let updater = UpdaterController()
        (self.security, self.host, self.viewer, self.pairing, self.agent, self.updater) = (security, host, viewer, pairing, agent, updater)
        // Bật chia sẻ ngay khi mở app để điện thoại tìm thấy Mac mà không cần vào menu.
        Task { @MainActor in await host.start() }
        host.usb.start()
        Task { @MainActor in await agent.restoreIfEnabled() }
        #if DEBUG
        Task { @MainActor in await AutomationHooks.run(host: host, viewer: viewer, security: security, pairing: pairing, agent: agent) }
        #endif
    }
}

enum ViewerBrowserWindow { static let id = "viewer-browser" }
enum AgentSettingsWindow { static let id = "agent-settings" }
