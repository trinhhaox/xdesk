import SwiftUI

@main
struct XdeskIOSApp: App {
    @State private var model = StreamViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if model.inStream { StreamView(model: model) } else { HostListView(model: model) }
            }
            .onChange(of: model.session.state) { _, state in
                UIApplication.shared.isIdleTimerDisabled = state == .streaming || state == .connecting
                model.failIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: Task { await model.enterBackground() }
                case .active: Task { await model.enterForeground() }
                default: break
                }
            }
            #if DEBUG
            .task { await AutomationHooks.run(model) }
            #endif
        }
    }
}
