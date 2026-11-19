import Foundation
import XdeskAgent

/// `xdesk_request_control`: hỏi người dùng (Mac + điện thoại), được phép thì tạo màn hình agent mặc định.
struct RequestControlTool: ToolHandler {
    let runtime: AgentRuntime

    func call(arguments: JsonValue) async -> ToolResult {
        let reason = String(arguments["reason"]?.stringValue?.prefix(300) ?? "")
        let name = await runtime.clientName
        guard case .granted = await runtime.arbiter.request(agentName: name, reason: reason) else {
            let denied = await runtime.arbiter.snapshot
            return .error("Không được cấp quyền: \(denied.reason ?? "người dùng từ chối hoặc không trả lời kịp")", audit: "denied")
        }
        do {
            let geometry = try await runtime.prepareDisplay()
            return .ok("Đã được cấp quyền điều khiển màn hình agent. \(geometry.coordinateNote)")
        } catch {
            await runtime.arbiter.end(reason: error.localizedDescription)
            return .error(error.localizedDescription)
        }
    }
}

struct EndControlTool: ToolHandler {
    let runtime: AgentRuntime

    func call(arguments: JsonValue) async -> ToolResult {
        let had = await runtime.arbiter.end(reason: "agent đã nhả quyền")
        return .ok(had ? "Đã nhả quyền điều khiển. Màn hình agent vẫn còn để người dùng xem lại." : "Không có quyền nào đang giữ.")
    }
}
