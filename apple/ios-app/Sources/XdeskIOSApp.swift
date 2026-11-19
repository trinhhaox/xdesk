import SwiftUI

@main
struct XdeskIOSApp: App {
    @State private var model = StreamViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearanceSetting.storageKey) private var appearanceRaw = AppearanceSetting.dark.rawValue

    var body: some Scene {
        WindowGroup {
            Group {
                if model.inStream { StreamView(model: model) } else { HostListView(model: model) }
            }
            .tint(BrandPalette.primary)
            .preferredColorScheme((AppearanceSetting(rawValue: appearanceRaw) ?? .dark).colorScheme)
            .onChange(of: model.session.state) { _, state in
                UIApplication.shared.isIdleTimerDisabled = state == .streaming || state == .connecting
                model.failIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    model.stopUsbListener()
                    Task { await model.enterBackground() }
                case .active:
                    model.startUsbListener()
                    Task { await model.enterForeground() }
                default: break
                }
            }
            .task { model.startUsbListener() }
            #if DEBUG
            .task { await AutomationHooks.run(model) }
            #endif
        }
    }
}
