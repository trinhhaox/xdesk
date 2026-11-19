import Foundation
import XdeskAgent

struct UiTreeTool: ToolHandler {
    let runtime: AgentRuntime

    func call(arguments: JsonValue) async -> ToolResult {
        guard AccessibilityPermission.isGranted else { return .error("Thiếu quyền Trợ năng cho Xdesk. \(AccessibilityPermission.guidance)") }
        guard case .success(let context) = await runtime.requireDisplay() else { return .error("Chưa có màn hình agent.") }
        let bounds = context.bounds
        let result = await Task.detached { AxTreeReader().read(in: bounds) }.value
        runtime.refs.replace(with: result.elements)
        let header = "\(result.elements.count) phần tử\(result.truncated ? " (đã cắt do giới hạn độ sâu/thời gian/số lượng; dùng xdesk_screenshot bổ sung)" : ""). Ref sống tới lần xdesk_ui_tree sau; toạ độ [x,y,w,h] theo màn hình agent."
        return .ok(([header] + result.elements.map(\.line)).joined(separator: "\n"))
    }
}
