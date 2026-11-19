import Foundation

/// `xdesk_run_steps`: tối đa 20 bước pointer/scroll/type/keys, dừng ở lỗi đầu tiên. Mỗi bước đi qua handler (đã bọc cổng quyền)
/// nên nếu người dùng tạm dừng giữa chừng thì bước kế tiếp dừng ngay.
public struct RunStepsTool: ToolHandler {
    public static let maxSteps = 20
    public static let allowedTools: Set<String> = ["xdesk_pointer", "xdesk_scroll", "xdesk_type_text", "xdesk_press_keys"]

    private let handlers: [String: any ToolHandler]
    private let schemas: [String: JsonValue]

    public init(handlers: [String: any ToolHandler], definitions: [ToolDefinition] = ToolSchemas.all) {
        self.handlers = handlers
        schemas = Dictionary(definitions.map { ($0.name, $0.inputSchema) }, uniquingKeysWith: { first, _ in first })
    }

    public func call(arguments: JsonValue) async -> ToolResult {
        guard case .array(let steps)? = arguments["steps"] else { return .error("Thiếu steps") }
        guard !steps.isEmpty else { return .error("steps rỗng") }
        guard steps.count <= Self.maxSteps else { return .error("Tối đa \(Self.maxSteps) bước (đang có \(steps.count))") }
        var lines: [String] = []
        for (index, step) in steps.enumerated() {
            let label = "Bước \(index + 1)"
            guard let name = step["tool"]?.stringValue, Self.allowedTools.contains(name), let handler = handlers[name], let schema = schemas[name] else {
                return .error((lines + ["\(label): tool không hợp lệ"]).joined(separator: "\n"), audit: "steps=\(index)/\(steps.count)")
            }
            let stepArguments = step["arguments"] ?? [:]
            if let problem = SchemaValidator.validate(stepArguments, against: schema, path: "\(label).arguments") {
                return .error((lines + [problem]).joined(separator: "\n"), audit: "steps=\(index)/\(steps.count)")
            }
            let result = await handler.call(arguments: stepArguments)
            lines.append("\(label) \(name): \(result.isError ? "LỖI" : "ok") \(result.text)")
            if result.isError { return .error(lines.joined(separator: "\n"), audit: "steps=\(index + 1)/\(steps.count)") }
        }
        return .ok(lines.joined(separator: "\n"), audit: "steps=\(steps.count)/\(steps.count)")
    }
}
