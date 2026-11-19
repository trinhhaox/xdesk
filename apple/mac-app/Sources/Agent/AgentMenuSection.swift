import SwiftUI

/// Mục menu cho MCP: bật/tắt, sao chép lệnh cấu hình, đổi token.
struct AgentMenuSection: View {
    let agent: AgentController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Cho phép agent AI (MCP)", isOn: Binding(
            get: { agent.isEnabled },
            set: { enabled in Task { await agent.setEnabled(enabled) } }))
        switch agent.status {
        case .running(let port): Text("Agent AI: 127.0.0.1:\(port)")
        case .failed(let message): Text("Agent AI lỗi: \(message)")
        case .stopped: EmptyView()
        }
        if case .running = agent.status {
            Button("Sao chép lệnh cấu hình") { agent.copySetupCommand() }
            Button("Đổi token") { agent.rotateToken() }
            Text("Quyền điều khiển: \(agent.controlSummary)")
            Text("Dừng nhanh: \(StopHotkey.label)")
            if agent.inputMonitorMissing { Text("Thiếu quyền Giám sát đầu vào: chưa tự dừng khi bạn chạm màn hình agent") }
            if agent.hasAgentDisplay { Button("Gỡ màn hình agent") { agent.removeAgentDisplay() } }
        }
        Button("Cài đặt agent AI…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: AgentSettingsWindow.id)
        }
        if let notice = agent.notice { Text(notice) }
    }
}
