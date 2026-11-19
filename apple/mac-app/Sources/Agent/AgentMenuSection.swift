import SwiftUI

/// Mục menu cho MCP: bật/tắt, sao chép lệnh cấu hình, đổi token.
struct AgentMenuSection: View {
    let agent: AgentController

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
        }
        if let notice = agent.notice { Text(notice) }
    }
}
