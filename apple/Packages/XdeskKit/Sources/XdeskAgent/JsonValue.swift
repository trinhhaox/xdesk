import Foundation

/// Giá trị JSON tự do (Codable) cho JSON-RPC và JSON Schema; viết schema bằng literal Swift cho gọn.
public enum JsonValue: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JsonValue])
    case object([String: JsonValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JsonValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JsonValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public static func decode(_ data: Data) throws -> JsonValue {
        try JSONDecoder().decode(JsonValue.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        return try encoder.encode(self)
    }

    public var stringValue: String? { if case .string(let value) = self { value } else { nil } }
    public var objectValue: [String: JsonValue]? { if case .object(let value) = self { value } else { nil } }
    public subscript(key: String) -> JsonValue? { objectValue?[key] }
}

extension JsonValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}
extension JsonValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}
extension JsonValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}
extension JsonValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JsonValue...) { self = .array(elements) }
}
extension JsonValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JsonValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
