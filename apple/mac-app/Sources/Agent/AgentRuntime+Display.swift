import Foundation
import XdeskAgent

extension AgentRuntime {
    /// Tạo màn hình agent mặc định nếu chưa có (gọi sau khi người dùng đã duyệt).
    func prepareDisplay() throws -> AgentDisplayGeometry {
        try displays.ensure()
        banner?.update(control, displayID: displays.displayID)
        guard let geometry = displays.geometry else { throw AgentDisplayError.unavailable("không đọc được kích thước") }
        return geometry
    }

    func resizeDisplay(width: Int, height: Int) async throws -> AgentDisplayGeometry {
        try await displays.recreate(width: width, height: height)
        refs.replace(with: [])
        banner?.update(control, displayID: displays.displayID)
        guard let geometry = displays.geometry else { throw AgentDisplayError.unavailable("không đọc được kích thước") }
        return geometry
    }

    func removeDisplay() {
        displays.destroy()
        refs.replace(with: [])
        banner?.hide()
    }

    /// 15 tool: status/request/end không cần quyền; mọi tool khác đi qua cổng `ControlArbiter`.
    func makeRegistry(host: HostController) -> ToolRegistry {
        func gated(_ tool: any ToolHandler) -> any ToolHandler { ControlledTool(arbiter: arbiter, inner: tool) }
        let steps: [String: any ToolHandler] = [
            "xdesk_pointer": gated(PointerTool(runtime: self)),
            "xdesk_scroll": gated(ScrollTool(runtime: self)),
            "xdesk_type_text": gated(TypeTextTool(runtime: self)),
            "xdesk_press_keys": gated(PressKeysTool(runtime: self)),
        ]
        var handlers = steps
        handlers["xdesk_status"] = StatusTool(snapshot: { [host] in await host.agentSnapshot() }, agent: { [weak self] in await self?.status() ?? AgentStatus() })
        handlers["xdesk_request_control"] = RequestControlTool(runtime: self)
        handlers["xdesk_end_control"] = EndControlTool(runtime: self)
        handlers["xdesk_screenshot"] = gated(ScreenshotTool(runtime: self))
        handlers["xdesk_ui_tree"] = gated(UiTreeTool(runtime: self))
        handlers["xdesk_run_steps"] = gated(RunStepsTool(handlers: steps))
        handlers["xdesk_launch"] = gated(LaunchTool(runtime: self))
        handlers["xdesk_set_workspace_size"] = gated(SetWorkspaceSizeTool(runtime: self))
        handlers["xdesk_clipboard_read"] = gated(ClipboardReadTool())
        handlers["xdesk_clipboard_write"] = gated(ClipboardWriteTool())
        handlers["xdesk_request_user_help"] = gated(RequestUserHelpTool(runtime: self))
        return ToolRegistry(handlers: handlers)
    }
}
