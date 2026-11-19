import CoreGraphics
import Foundation
import XdeskAgent

/// Cuộn tại vị trí con trỏ; con trỏ phải đang nằm trên màn hình agent (dùng xdesk_pointer move trước).
struct ScrollTool: ToolHandler {
    let runtime: AgentRuntime

    func call(arguments: JsonValue) async -> ToolResult {
        guard case .success(let context) = await runtime.requireDisplay() else { return .error("Chưa có màn hình agent.") }
        let dx = arguments.number("dx") ?? 0, dy = arguments.number("dy") ?? 0
        guard abs(dx) <= 10_000, abs(dy) <= 10_000 else { return .error("dx/dy tối đa 10000 px") }
        guard let cursor = CGEvent(source: nil)?.location, context.bounds.contains(cursor) else {
            return .error("Con trỏ không ở trên màn hình agent. Hãy xdesk_pointer move vào vùng cần cuộn trước.")
        }
        if let refusal = await runtime.checkApp(under: cursor) { return .error(refusal, audit: "app_refused") }
        runtime.poster.scroll(dx: Int32(dx), dy: Int32(dy))
        return .ok("Đã cuộn dx=\(Int(dx)) dy=\(Int(dy))")
    }
}
