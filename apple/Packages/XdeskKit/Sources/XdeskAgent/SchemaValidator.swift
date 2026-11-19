import Foundation

/// Kiểm tham số tool theo tập con JSON Schema mà `ToolSchemas` dùng: type, enum, required, properties,
/// additionalProperties:false, items, maxItems. Trả mô tả lỗi đầu tiên (tiếng Việt) hoặc nil.
public enum SchemaValidator {
    public static func validate(_ value: JsonValue, against schema: JsonValue, path: String = "arguments") -> String? {
        if let type = schema["type"]?.stringValue, let problem = checkType(value, type, path) { return problem }
        if case .array(let allowed)? = schema["enum"], !allowed.contains(value) {
            let names = allowed.compactMap(\.stringValue).joined(separator: ", ")
            return "\(path) phải là một trong: \(names)"
        }
        switch value {
        case .object(let object): return validateObject(object, schema, path)
        case .array(let items): return validateArray(items, schema, path)
        default: return nil
        }
    }

    private static func validateObject(_ object: [String: JsonValue], _ schema: JsonValue, _ path: String) -> String? {
        if case .array(let required)? = schema["required"] {
            for case .string(let key) in required where object[key] == nil { return "\(path).\(key) là bắt buộc" }
        }
        let properties = schema["properties"]?.objectValue ?? [:]
        for key in object.keys.sorted() {
            guard let sub = properties[key] else {
                if case .bool(false)? = schema["additionalProperties"] { return "\(path).\(key) không nằm trong schema" }
                continue
            }
            if let problem = validate(object[key] ?? .null, against: sub, path: "\(path).\(key)") { return problem }
        }
        return nil
    }

    private static func validateArray(_ items: [JsonValue], _ schema: JsonValue, _ path: String) -> String? {
        if case .int(let limit)? = schema["maxItems"], items.count > limit { return "\(path) tối đa \(limit) phần tử (đang có \(items.count))" }
        guard let itemSchema = schema["items"] else { return nil }
        for (index, item) in items.enumerated() {
            if let problem = validate(item, against: itemSchema, path: "\(path)[\(index)]") { return problem }
        }
        return nil
    }

    private static func checkType(_ value: JsonValue, _ type: String, _ path: String) -> String? {
        let matches: Bool
        switch (type, value) {
        case ("object", .object), ("array", .array), ("string", .string), ("boolean", .bool), ("number", .int), ("number", .double): matches = true
        case ("integer", .int): matches = true
        case ("integer", .double(let number)): matches = number.rounded() == number
        default: matches = false
        }
        return matches ? nil : "\(path) phải có kiểu \(type)"
    }
}
