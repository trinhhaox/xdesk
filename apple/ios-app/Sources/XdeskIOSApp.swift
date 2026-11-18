import SwiftUI

@main
struct XdeskIOSApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Image(systemName: "display.2")
                    .font(.system(size: 56))
                Text("Xdesk")
                    .font(.largeTitle.bold())
                Text("Chưa kết nối máy Mac nào")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
