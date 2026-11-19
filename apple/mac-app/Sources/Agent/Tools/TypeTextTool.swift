import Carbon.HIToolbox
import Foundation
import XdeskAgent

/// Gõ chuỗi Unicode. Từ chối khi đang bật Secure Event Input hoặc phần tử focus là ô mật khẩu. Nhật ký chỉ ghi độ dài.
struct TypeTextTool: ToolHandler {
    static let maxChars = 5_000
    let runtime: AgentRuntime

    func call(arguments: JsonValue) async -> ToolResult {
        guard let text = arguments["text"]?.stringValue, !text.isEmpty else { return .error("text rỗng") }
        let audit = "chars=\(text.count)"
        guard text.count <= Self.maxChars else { return .error("Tối đa \(Self.maxChars) ký tự mỗi lần gõ", audit: audit) }
        guard case .success(let context) = await runtime.requireDisplay() else { return .error("Chưa có màn hình agent.", audit: audit) }
        if let refusal = SecureInputGuard.refusal() { return .error(refusal, audit: audit + " secure") }
        if let refusal = await runtime.checkFocused(in: context) { return .error(refusal, audit: audit) }
        do { try await runtime.poster.type(text) } catch { return .error("Bị huỷ giữa chừng: \(error.localizedDescription)", audit: audit) }
        return .ok("Đã gõ \(text.count) ký tự", audit: audit)
    }
}

enum SecureInputGuard {
    static func refusal() -> String? {
        if IsSecureEventInputEnabled() { return "Từ chối: macOS đang bật Secure Event Input (có ô mật khẩu đang nhận phím). Không gõ để tránh lộ/ghi nhầm mật khẩu." }
        if AgentTargeting.focusedElementIsSecure() { return "Từ chối: phần tử đang focus là ô mật khẩu (AXSecureTextField)." }
        return nil
    }
}
