import SwiftUI

@main
struct XdeskMacApp: App {
    var body: some Scene {
        MenuBarExtra("Xdesk", systemImage: "display.2") {
            Text("Xdesk")
            Divider()
            Button("Thoát Xdesk") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
