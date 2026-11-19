import Foundation
import XdeskAgent

struct PressKeysTool: ToolHandler {
    let runtime: AgentRuntime

    func call(arguments: JsonValue) async -> ToolResult {
        guard case .array(let raw)? = arguments["keys"] else { return .error("Thiếu keys") }
        let chord: KeyChord
        do { chord = try KeyChord.parse(raw.compactMap(\.stringValue)) } catch { return .error("keys không hợp lệ: \(error)") }
        guard case .success(let context) = await runtime.requireDisplay() else { return .error("Chưa có màn hình agent.") }
        // Phím thường (không ⌘/⌃) có thể gõ chữ vào ô mật khẩu nên chịu cùng bảo vệ như xdesk_type_text.
        if chord.modifiers.isDisjoint(with: [.command, .control]), let refusal = SecureInputGuard.refusal() { return .error(refusal) }
        if let refusal = await runtime.checkFocused(in: context) { return .error(refusal, audit: "app_refused") }
        do { try await runtime.poster.press(chord) } catch { return .error("Bị huỷ: \(error.localizedDescription)") }
        return .ok("Đã nhấn \(raw.compactMap(\.stringValue).joined(separator: "+"))")
    }
}
