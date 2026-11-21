import Foundation
import XdeskAgent

/// `xdesk_request_user_help`: yêu cầu người dùng can thiệp (giải CAPTCHA, 2FA, OTP...) và chờ người dùng hoàn thành.
struct RequestUserHelpTool: ToolHandler {
    let runtime: AgentRuntime

    func call(arguments: JsonValue) async -> ToolResult {
        let reason = String(arguments["reason"]?.stringValue?.prefix(300) ?? "Cần người dùng hỗ trợ")
        let timeoutSeconds = arguments.number("timeoutSeconds").map { Int($0) } ?? 120
        let timeout = max(10, min(600, timeoutSeconds))
        let success = await runtime.requestUserHelp(reason: reason, timeoutSeconds: timeout)
        if success {
            return .ok("Người dùng đã hoàn thành can thiệp. Bạn có thể tiếp tục thao tác trên màn hình agent.")
        } else {
            return .error("Người dùng chưa hoàn thành can thiệp hoặc hết thời gian chờ (\(timeout)s).", audit: "timeout")
        }
    }
}
