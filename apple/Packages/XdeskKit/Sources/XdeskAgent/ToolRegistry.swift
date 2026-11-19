import Foundation

public struct ToolImage: Sendable, Equatable {
    public var mimeType: String
    public var base64: String
    public init(mimeType: String, base64: String) { self.mimeType = mimeType; self.base64 = base64 }
}

public struct ToolResult: Sendable, Equatable {
    public var text: String
    public var isError: Bool
    public var images: [ToolImage]
    /// Ghi chú ngắn cho nhật ký (ví dụ độ dài chuỗi gõ). Không bao giờ chứa nội dung người dùng/ảnh.
    public var audit: String?

    public init(text: String, isError: Bool, images: [ToolImage] = [], audit: String? = nil) {
        self.text = text; self.isError = isError; self.images = images; self.audit = audit
    }

    public static func ok(_ text: String, images: [ToolImage] = [], audit: String? = nil) -> ToolResult {
        ToolResult(text: text, isError: false, images: images, audit: audit)
    }
    public static func error(_ text: String, audit: String? = nil) -> ToolResult { ToolResult(text: text, isError: true, audit: audit) }

    /// Lỗi của tool đi qua `isError` trong kết quả, không phải lỗi JSON-RPC, để model đọc và tự sửa.
    var json: JsonValue {
        let blocks: [JsonValue] = [["type": "text", "text": .string(text)]]
            + images.map { ["type": "image", "data": .string($0.base64), "mimeType": .string($0.mimeType)] }
        return ["content": .array(blocks), "isError": .bool(isError)]
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

/// Danh sách tool + handler. Tham số được kiểm theo JSON Schema trước khi tới handler.
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
        guard let definition = definitions.first(where: { $0.name == name }) else { return nil }
        if let problem = SchemaValidator.validate(arguments, against: definition.inputSchema) {
            return .error("Tham số không hợp lệ: \(problem)")
        }
        return await (handlers[name] ?? UnsupportedToolHandler()).call(arguments: arguments)
    }
}
