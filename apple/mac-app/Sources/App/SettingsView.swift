import SwiftUI

/// Cửa sổ Cài đặt (⌘,): gom các công tắc và cửa sổ trước đây nằm rải rác trong menu.
struct SettingsView: View {
    let host: HostController
    let security: SecurityCenter
    let agent: AgentController
    let updater: UpdaterController

    var body: some View {
        TabView {
            GeneralSettingsPane(host: host)
                .tabItem { Label("Chung", systemImage: "gearshape") }
            ConnectionSettingsPane(host: host)
                .tabItem { Label("Kết nối", systemImage: "network") }
            DevicesSettingsPane(security: security, agent: agent)
                .tabItem { Label("Thiết bị", systemImage: "ipad.and.iphone") }
            AgentSettingsPane(agent: agent)
                .tabItem { Label("Agent AI", systemImage: "sparkles") }
            UpdateSettingsView(updater: updater)
                .frame(width: Self.width, height: 380)
                .tabItem { Label("Cập nhật", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: Self.width)
    }

    static let width: CGFloat = 560
}

struct DevicesSettingsPane: View {
    let security: SecurityCenter
    let agent: AgentController

    var body: some View {
        PairedDevicesSettings(security: security, embedded: true) {
            PermissionsSection(agent: agent)
        }
        .frame(width: SettingsView.width, height: 560)
    }
}

/// Trạng thái từng quyền hệ thống, đọc lại định kỳ vì người dùng bật quyền ở Cài đặt hệ thống.
struct PermissionsSection: View {
    let agent: AgentController
    @State private var system = SystemSnapshot()
    private let ticker = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        Section("Quyền của Xdesk") {
            row(.screenRecording, granted: system.screenRecording)
            row(.accessibility, granted: system.accessibility)
            if agent.isEnabled { row(.inputMonitoring, granted: !agent.inputMonitorMissing) }
        }
        .onAppear { system = SystemSnapshot() }
        .onReceive(ticker) { _ in system = SystemSnapshot() }
    }

    private func row(_ kind: PermissionKind, granted: Bool) -> some View {
        LabeledContent {
            if granted {
                Label("Đã cấp", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
            } else {
                Button("Mở Cài đặt") { if let url = kind.settingsURL { NSWorkspace.shared.open(url) } }
                    .accessibilityLabel("Mở Cài đặt để cấp quyền \(kind.title)")
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                Text(kind.reason).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
