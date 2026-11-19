import SwiftUI

/// Tab "Agent AI": công tắc MCP, địa chỉ, lệnh cấu hình, token, trạng thái điều khiển + các luật có sẵn của `AgentSettingsView`.
struct AgentSettingsPane: View {
    let agent: AgentController

    var body: some View {
        Form {
            Section("Máy chủ MCP") {
                Toggle("Cho phép agent AI (MCP)", isOn: Binding(
                    get: { agent.isEnabled }, set: { enabled in Task { await agent.setEnabled(enabled) } }))
                switch agent.status {
                case .running(let port):
                    LabeledContent("Địa chỉ") { Text(verbatim: EndpointFormat.hostPort("127.0.0.1", port)).textSelection(.enabled) }
                    LabeledContent("Quyền điều khiển") { Text(agent.controlSummary) }
                    LabeledContent("Dừng nhanh") { Text(StopHotkey.label) }
                    HStack {
                        Button("Sao chép lệnh cấu hình") { agent.copySetupCommand() }
                        Button("Đổi token") { agent.rotateToken() }
                        if agent.hasAgentDisplay { Button("Gỡ màn hình agent") { agent.removeAgentDisplay() } }
                    }
                    if agent.inputMonitorMissing {
                        Label("Thiếu quyền Giám sát đầu vào: chưa tự dừng khi bạn chạm màn hình agent.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(BrandPalette.warning).font(.footnote)
                    }
                case .failed(let message):
                    Label("Agent AI lỗi: \(message)", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                case .stopped:
                    Text("Đang tắt. Bật để agent AI (Claude Code, Cursor…) điều khiển Mac qua MCP trên 127.0.0.1.").font(.footnote).foregroundStyle(.secondary)
                }
                if let notice = agent.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
            }
            AgentSettingsView(settings: agent.settings)
        }
        .formStyle(.grouped)
        .frame(width: SettingsView.width, height: 580)
    }
}
