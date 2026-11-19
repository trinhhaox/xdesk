import Foundation
import Testing
@testable import XdeskAgent

private func raw(_ text: String) -> Data { Data(text.utf8) }

@Suite struct HttpRequestParserTests {
    @Test func parsesPostWithBodyAndLowercasesHeaders() {
        let body = #"{"a":1}"#
        let data = raw("POST /mcp?x=1 HTTP/1.1\r\nHost: 127.0.0.1:47810\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)")
        guard case .request(let request, let consumed) = HttpRequestParser.parse(data) else { Issue.record("phải parse được"); return }
        #expect(request.method == "POST")
        #expect(request.path == "/mcp")
        #expect(request.headers["host"] == "127.0.0.1:47810")
        #expect(request.body == raw(body))
        #expect(consumed == data.count)
    }

    @Test func waitsForRestOfHeadersAndBody() {
        #expect(HttpRequestParser.parse(raw("POST /mcp HTTP/1.1\r\nHost: x")) == .needMore)
        #expect(HttpRequestParser.parse(raw("POST /mcp HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc")) == .needMore)
    }

    @Test func getWithoutBody() {
        guard case .request(let request, _) = HttpRequestParser.parse(raw("GET /mcp HTTP/1.1\r\nHost: a\r\n\r\n")) else { Issue.record("phải parse được"); return }
        #expect(request.body.isEmpty)
    }

    @Test func rejectsBodyOverOneMiB() {
        let data = raw("POST /mcp HTTP/1.1\r\nContent-Length: \((1 << 20) + 1)\r\n\r\n")
        #expect(HttpRequestParser.parse(data) == .failure(status: 413, message: "Thân yêu cầu quá 1 MiB"))
    }

    @Test func acceptsBodyOfExactlyOneMiB() {
        let body = String(repeating: "a", count: 1 << 20)
        guard case .request(let request, _) = HttpRequestParser.parse(raw("POST /mcp HTTP/1.1\r\nContent-Length: \(1 << 20)\r\n\r\n\(body)")) else {
            Issue.record("phải parse được"); return
        }
        #expect(request.body.count == 1 << 20)
    }

    @Test func rejectsOversizedHeaders() {
        let data = raw("GET /mcp HTTP/1.1\r\nX: " + String(repeating: "a", count: 20_000))
        #expect(HttpRequestParser.parse(data) == .failure(status: 431, message: "Header quá lớn"))
    }

    @Test(arguments: [
        "GET /mcp\r\n\r\n",
        "GET /mcp HTTP/2\r\n\r\n",
        "GET http://evil.com/mcp HTTP/1.1\r\n\r\n",
        "GET /mcp HTTP/1.1\r\nBadHeader\r\n\r\n",
        "GET /mcp HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n",
        "POST /mcp HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n",
        "POST /mcp HTTP/1.1\r\nContent-Length: -1\r\n\r\n",
        "POST /mcp HTTP/1.1\r\nContent-Length: 1a\r\n\r\n",
        "GET /mcp HTTP/1.1\r\n folded: x\r\n\r\n",
    ])
    func rejectsMalformed(_ text: String) {
        guard case .failure(let status, _) = HttpRequestParser.parse(raw(text)) else { Issue.record("phải bị từ chối: \(text)"); return }
        #expect(status == 400)
    }

    @Test func rejectsChunkedEncoding() {
        let data = raw("POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n")
        #expect(HttpRequestParser.parse(data) == .failure(status: 501, message: "Không hỗ trợ Transfer-Encoding"))
    }

    @Test func responseSerializationAlwaysClosesConnection() {
        let text = String(decoding: HttpResponse.failure(status: 405, message: "x", headers: ["Allow": "POST"]).serialized(), as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 405 Method Not Allowed\r\n"))
        #expect(text.contains("Connection: close\r\n"))
        #expect(text.contains("Allow: POST\r\n"))
        #expect(text.hasSuffix(#"{"error":"x"}"#))
    }
}
