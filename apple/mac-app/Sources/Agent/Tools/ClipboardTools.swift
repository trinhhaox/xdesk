import AppKit
import Foundation
import XdeskAgent
import XdeskClipboard

struct ClipboardReadTool: ToolHandler {
    static let maxChars = 10_000

    func call(arguments: JsonValue) async -> ToolResult {
        await MainActor.run {
            let board = NSPasteboard.general
            let types = (board.types ?? []).map(\.rawValue)
            if let reason = ClipboardPolicy.refusalReason(types: types) { return .ok("[rỗng] Lý do: \(reason)", audit: "concealed") }
            guard let text = board.string(forType: .string), !text.isEmpty else { return .ok("[rỗng] Clipboard không có văn bản", audit: "chars=0") }
            return .ok(String(text.prefix(Self.maxChars)), audit: "chars=\(min(text.count, Self.maxChars))")
        }
    }
}

struct ClipboardWriteTool: ToolHandler {
    func call(arguments: JsonValue) async -> ToolResult {
        guard let text = arguments["text"]?.stringValue else { return .error("Thiếu text") }
        guard text.count <= ClipboardReadTool.maxChars else { return .error("Tối đa \(ClipboardReadTool.maxChars) ký tự") }
        return await MainActor.run {
            let board = NSPasteboard.general
            board.clearContents()
            return board.setString(text, forType: .string) ? .ok("Đã ghi \(text.count) ký tự", audit: "chars=\(text.count)") : .error("Không ghi được clipboard")
        }
    }
}
