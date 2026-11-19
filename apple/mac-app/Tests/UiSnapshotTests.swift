import AppKit
import SwiftUI
import Testing
@testable import Xdesk

/// Vẽ giao diện mới ra PNG ngoài màn hình (cửa sổ không bao giờ hiện) để kiểm tra bố cục. Chỉ chạy khi đặt
/// `TEST_RUNNER_XDESK_UI_SNAPSHOT_DIR`; bình thường bỏ qua để test không ghi tệp.
@MainActor
@Suite struct UiSnapshotTests {
    static let sessions: [PopoverState.Session] = [
        .init(id: UUID(), info: ViewerSessionInfo(name: "iPad Pro của Hào", transport: .lan, modeLabel: "Bản sao · Vừa thiết bị")),
        .init(id: UUID(), info: ViewerSessionInfo(name: "iPhone 14 Pro Max", transport: .tailscale, modeLabel: "Mở rộng")),
    ]

    static var states: [(String, PopoverState)] {
        let channels = PopoverState(lanText: "192.168.1.23:47800", tailscaleText: "Tailscale 100.76.38.107:47800")
        var stopped = channels
        stopped.tailscaleText = "Tailscale: tắt"
        var sharing = channels
        (sharing.pill, sharing.isHosting, sharing.sessions) = (.sharing, true, sessions)
        sharing.usb = [.init(id: 1, label: "A1B2C3D4")]
        var missing = channels
        (missing.pill, missing.missing, missing.errorMessage) = (.needsPermission, [.screenRecording, .accessibility, .inputMonitoring], nil)
        missing.updateVersion = "0.2.0"
        return [("stopped", stopped), ("sharing", sharing), ("permissions", missing)]
    }

    @Test func renderPopoverAndSettingsSnapshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["XDESK_UI_SNAPSHOT_DIR"], !dir.isEmpty else { return }
        let base = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        for (name, state) in Self.states {
            for scheme in [ColorScheme.light, .dark] {
                try Self.render(MenuPopoverView(state: state, actions: PopoverActions()), scheme: scheme, to: base.appendingPathComponent("popover-\(name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
        let host = HostController(security: SecurityCenter())
        let agent = AgentController(host: host, defaults: UserDefaults(suiteName: "xdesk.ui-snapshot") ?? .standard)
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            try Self.render(GeneralSettingsPane(host: host), scheme: scheme, to: base.appendingPathComponent("settings-general-\(suffix).png"))
            try Self.render(ConnectionSettingsPane(host: host), scheme: scheme, to: base.appendingPathComponent("settings-connection-\(suffix).png"))
            try Self.render(AgentSettingsPane(agent: agent), scheme: scheme, to: base.appendingPathComponent("settings-agent-\(suffix).png"))
            try Self.render(Form { PermissionsSection(agent: agent) }.formStyle(.grouped).frame(width: SettingsView.width, height: 220), scheme: scheme, to: base.appendingPathComponent("settings-permissions-\(suffix).png"))
        }
    }

    static func render<V: View>(_ view: V, scheme: ColorScheme, to url: URL) throws {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, scheme).background(Color(nsColor: .windowBackgroundColor)))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw CocoaError(.fileWriteUnknown) }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}
