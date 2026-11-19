import CoreGraphics
import Foundation
import XdeskAgent

struct PointerTool: ToolHandler {
    let runtime: AgentRuntime

    func call(arguments: JsonValue) async -> ToolResult {
        guard let action = arguments["action"]?.stringValue else { return .error("Thiếu action") }
        guard case .success(let context) = await runtime.requireDisplay() else { return .error("Chưa có màn hình agent.") }
        guard let (x, y) = resolve(arguments) else {
            return .error(arguments["ref"] != nil ? "ref không tồn tại hoặc đã hết hiệu lực, hãy gọi lại xdesk_ui_tree" : "Cần x,y hoặc ref")
        }
        guard let point = await runtime.globalPoint(x: x, y: y, in: context) else {
            return .error("Toạ độ (\(Int(x)),\(Int(y))) nằm ngoài màn hình agent \(context.geometry.width)x\(context.geometry.height)")
        }
        var end: CGPoint?
        if action == "drag" {
            guard let toX = arguments.number("toX"), let toY = arguments.number("toY"),
                  let target = await runtime.globalPoint(x: toX, y: toY, in: context) else { return .error("drag cần toX,toY nằm trong màn hình agent") }
            end = target
        }
        if let refusal = await runtime.checkApp(under: point) { return .error(refusal, audit: "app_refused") }
        let poster = runtime.poster
        do {
            switch action {
            case "move": poster.move(to: point)
            case "click": try await poster.click(at: point)
            case "double": try await poster.click(at: point, count: 2)
            case "right": try await poster.click(at: point, button: .right)
            case "drag": if let end { try await poster.drag(from: point, to: end) }
            default: return .error("action không hợp lệ: \(action)")
            }
        } catch { return .error("Bị huỷ: \(error.localizedDescription)") }
        return .ok("\(action) tại (\(Int(x)),\(Int(y)))")
    }

    private func resolve(_ arguments: JsonValue) -> (Double, Double)? {
        if let ref = arguments["ref"]?.stringValue { return runtime.refs.element(ref)?.center }
        guard let x = arguments.number("x"), let y = arguments.number("y") else { return nil }
        return (x, y)
    }
}
