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
        #if DEBUG
        let host = host, viewer = viewer
        Task { @MainActor in await AutomationHooks.run(host: host, viewer: viewer) }
        #endif
    }
}

enum ViewerBrowserWindow { static let id = "viewer-browser" }
