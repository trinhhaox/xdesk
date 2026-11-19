import Foundation

public enum HttpParseResult: Sendable, Equatable {
    case needMore
    /// `consumed` là số byte đã dùng; vì mỗi kết nối chỉ phục vụ một yêu cầu nên phần dư bị bỏ.
    case request(HttpRequest, consumed: Int)
    case failure(status: Int, message: String)
}

/// HTTP/1.1 tối thiểu: dòng yêu cầu + header + thân theo Content-Length (không chunked, không pipelining).
public enum HttpRequestParser {
    public static let maxHeaderBytes = 16 * 1024
    public static let maxBodyBytes = 1 << 20

    public static func parse(_ buffer: Data) -> HttpParseResult {
        let terminator = Data("\r\n\r\n".utf8)
        guard let end = buffer.range(of: terminator) else {
            return buffer.count > maxHeaderBytes ? .failure(status: 431, message: "Header quá lớn") : .needMore
        }
        guard end.lowerBound <= maxHeaderBytes else { return .failure(status: 431, message: "Header quá lớn") }
        guard let head = String(data: buffer[buffer.startIndex..<end.lowerBound], encoding: .utf8) else {
            return .failure(status: 400, message: "Header không phải UTF-8")
        }
        let lines = head.components(separatedBy: "\r\n")
        let start: (method: String, path: String)
        switch parseRequestLine(lines[0]) {
        case .success(let value): start = value
        case .failure(let error): return .failure(status: 400, message: error.message)
        }
        let headers: [String: String]
        switch parseHeaders(lines.dropFirst()) {
        case .success(let value): headers = value
        case .failure(let error): return .failure(status: error.status, message: error.message)
        }
        if headers["transfer-encoding"] != nil { return .failure(status: 501, message: "Không hỗ trợ Transfer-Encoding") }
        let length: Int
        switch contentLength(headers) {
        case .success(let value): length = value
        case .failure(let error): return .failure(status: error.status, message: error.message)
        }
        let bodyStart = end.upperBound
        guard buffer.endIndex - bodyStart >= length else { return .needMore }
        let body = Data(buffer[bodyStart..<(bodyStart + length)])
        let request = HttpRequest(method: start.method, path: start.path, headers: headers, body: body)
        return .request(request, consumed: bodyStart + length - buffer.startIndex)
    }

    private struct ParseFailure: Error { let status: Int; let message: String }

    private static func parseRequestLine(_ line: String) -> Result<(method: String, path: String), ParseFailure> {
        let parts = line.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1."), parts[1].hasPrefix("/"), !parts[0].isEmpty else {
            return .failure(ParseFailure(status: 400, message: "Dòng yêu cầu không hợp lệ"))
        }
        let path = parts[1].split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        return .success((String(parts[0]), String(path)))
    }

    private static func parseHeaders(_ lines: ArraySlice<String>) -> Result<[String: String], ParseFailure> {
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex, !line.hasPrefix(" "), !line.hasPrefix("\t") else {
                return .failure(ParseFailure(status: 400, message: "Header không hợp lệ"))
            }
            let name = line[..<colon].lowercased()
            // Host/Content-Length lặp là dấu hiệu tấn công smuggling hoặc né kiểm Host.
            if headers[name] != nil, ["host", "content-length", "authorization", "origin"].contains(name) {
                return .failure(ParseFailure(status: 400, message: "Header \(name) bị lặp"))
            }
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return .success(headers)
    }

    private static func contentLength(_ headers: [String: String]) -> Result<Int, ParseFailure> {
        guard let raw = headers["content-length"] else { return .success(0) }
        guard !raw.isEmpty, raw.allSatisfy(\.isASCII), raw.allSatisfy(\.isNumber), let value = Int(raw) else {
            return .failure(ParseFailure(status: 400, message: "Content-Length không hợp lệ"))
        }
        guard value <= maxBodyBytes else { return .failure(ParseFailure(status: 413, message: "Thân yêu cầu quá 1 MiB")) }
        return .success(value)
    }
}
