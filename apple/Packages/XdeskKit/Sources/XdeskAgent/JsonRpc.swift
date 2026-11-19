import Foundation

public enum JsonRpcErrorCode {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
}

/// Một thông điệp JSON-RPC 2.0 đã phân loại. MCP 2025-06-18 trở đi không còn batch.
public enum JsonRpcMessage: Sendable, Equatable {
    case request(id: JsonValue, method: String, params: JsonValue)
    case notification(method: String)
    /// Phản hồi từ client cho request của server; server không gửi request nên chỉ cần nhận và bỏ qua.
    case response
    case batch
    case invalid(reason: String)
    case parseError

    public static func parse(_ body: Data) -> JsonRpcMessage {
        guard let value = try? JsonValue.decode(body) else { return .parseError }
        if case .array = value { return .batch }
        guard let object = value.objectValue, object["jsonrpc"] == "2.0" else {
            return .invalid(reason: "Thiếu jsonrpc \"2.0\"")
        }
        guard let method = object["method"] else {
            return object["result"] != nil || object["error"] != nil ? .response : .invalid(reason: "Thiếu method")
        }
        guard let name = method.stringValue else { return .invalid(reason: "method phải là chuỗi") }
        guard let id = object["id"] else { return .notification(method: name) }
        switch id {
        case .string, .int: return .request(id: id, method: name, params: object["params"] ?? [:])
        default: return .invalid(reason: "id phải là chuỗi hoặc số nguyên")
        }
    }
}

public enum JsonRpcResponse {
    public static func result(id: JsonValue, _ result: JsonValue) -> JsonValue {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    public static func error(id: JsonValue?, code: Int, message: String) -> JsonValue {
        ["jsonrpc": "2.0", "id": id ?? .null, "error": ["code": .int(code), "message": .string(message)]]
    }
}
