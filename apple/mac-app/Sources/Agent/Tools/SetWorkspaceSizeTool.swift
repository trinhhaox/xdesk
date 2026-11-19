import Foundation
import XdeskAgent

struct SetWorkspaceSizeTool: ToolHandler {
    let runtime: AgentRuntime

    func call(arguments: JsonValue) async -> ToolResult {
        guard let width = arguments.number("width"), let height = arguments.number("height"),
              width == width.rounded(), height == height.rounded() else { return .error("width/height phải là số nguyên") }
        do {
            let geometry = try await runtime.resizeDisplay(width: Int(width), height: Int(height))
            return .ok("Đã đổi màn hình agent. Các ref cũ đã hết hiệu lực, hãy gọi lại xdesk_ui_tree. \(geometry.coordinateNote)")
        } catch { return .error(error.localizedDescription) }
    }
}
