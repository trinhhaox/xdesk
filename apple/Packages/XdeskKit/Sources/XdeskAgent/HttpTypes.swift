import Foundation

/// Yêu cầu HTTP đã phân tích; tên header viết thường.
public struct HttpRequest: Sendable, Equatable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

public struct HttpResponse: Sendable, Equatable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public static func json(_ value: JsonValue, status: Int = 200, headers: [String: String] = [:]) -> HttpResponse {
        var all = headers
        all["Content-Type"] = "application/json"
        return HttpResponse(status: status, headers: all, body: (try? value.encoded()) ?? Data())
    }

    public static func empty(status: Int, headers: [String: String] = [:]) -> HttpResponse {
        HttpResponse(status: status, headers: headers)
    }

    /// Lỗi HTTP thuần (guard, định tuyến) với thân JSON `{"error": ...}`.
    public static func failure(status: Int, message: String, headers: [String: String] = [:]) -> HttpResponse {
        json(["error": .string(message)], status: status, headers: headers)
    }

    /// Dòng trạng thái + header + thân, luôn `Connection: close`.
    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        var all = headers
        all["Content-Length"] = String(body.count)
        all["Connection"] = "close"
        all["Cache-Control"] = "no-store"
        for (name, value) in all.sorted(by: { $0.key < $1.key }) { head += "\(name): \(value)\r\n" }
        return Data((head + "\r\n").utf8) + body
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 204: "No Content"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 411: "Length Required"
        case 413: "Content Too Large"
        case 429: "Too Many Requests"
        case 431: "Request Header Fields Too Large"
        case 501: "Not Implemented"
        default: "Status"
        }
    }
}
