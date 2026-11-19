import Foundation

public struct ToolResult: Sendable, Equatable {
    public var text: String
    public var isError: Bool

    public static func ok(_ text: String) -> ToolResult { ToolResult(text: text, isError: false) }
    public static func error(_ text: String) -> ToolResult { ToolResult(text: text, isError: true) }

    /// Lỗi của tool đi qua `isError` trong kết quả, không phải lỗi JSON-RPC, để model đọc và tự sửa.
    var json: JsonValue {
        ["content": [["type": "text", "text": .string(text)]], "isError": .bool(isError)]
    }
}

public protocol ToolHandler: Sendable {
    func call(arguments: JsonValue) async -> ToolResult
}

public struct UnsupportedToolHandler: ToolHandler {
    public init() {}
    public func call(arguments: JsonValue) async -> ToolResult { .error("Chưa hỗ trợ ở bản này (phase 08b)") }
}

public struct ToolDefinition: Sendable {
    public let name: String
    public let title: String
    public let description: String
    public let inputSchema: JsonValue
    public let readOnly: Bool
    public let destructive: Bool
    public let idempotent: Bool

    var listing: JsonValue {
        [
            "name": .string(name), "title": .string(title), "description": .string(description),
            "inputSchema": inputSchema,
            "annotations": [
                "title": .string(title), "readOnlyHint": .bool(readOnly), "destructiveHint": .bool(destructive),
                "idempotentHint": .bool(idempotent), "openWorldHint": false,
            ],
        ]
    }
}

/// Danh sách tool + handler. Tool chưa có handler trả "chưa hỗ trợ"; phase 08b thay dần bằng handler thật.
public struct ToolRegistry: Sendable {
    public let definitions: [ToolDefinition]
    private let handlers: [String: any ToolHandler]

    public init(definitions: [ToolDefinition] = ToolSchemas.all, handlers: [String: any ToolHandler] = [:]) {
        self.definitions = definitions
        self.handlers = handlers
    }

    public var listResult: JsonValue { ["tools": .array(definitions.map(\.listing))] }

    /// `nil` nghĩa là không có tool tên đó (lỗi giao thức -32602).
    public func call(name: String, arguments: JsonValue) async -> ToolResult? {
        guard definitions.contains(where: { $0.name == name }) else { return nil }
        return await (handlers[name] ?? UnsupportedToolHandler()).call(arguments: arguments)
    }
}
