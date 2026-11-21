import Foundation
import Testing
@testable import XdeskAgent

private let port: UInt16 = 47810
private let token = "test-token"

private func makeServer(audit: AuditLog? = nil, snapshot: HostSnapshot = HostSnapshot(isSharing: true, viewerCount: 2, encryptionOn: true)) -> McpServer {
    McpServer(
        requestGuard: RequestGuard(port: port, token: { token }),
        registry: ToolRegistry(handlers: ["xdesk_status": StatusTool(snapshot: { snapshot })]),
        audit: audit, serverVersion: "0.0.1")
}

private func post(_ json: String, session: String? = nil, extra: [String: String] = [:]) -> HttpRequest {
    var headers = ["host": "127.0.0.1:\(port)", "authorization": "Bearer \(token)"]
    if let session { headers["mcp-session-id"] = session }
    headers.merge(extra) { _, new in new }
    return HttpRequest(method: "POST", path: "/mcp", headers: headers, body: Data(json.utf8))
}

private func body(_ response: HttpResponse) -> JsonValue { (try? JsonValue.decode(response.body)) ?? .null }

private func openSession(_ server: McpServer, version: String = "2025-11-25") async -> String {
    let response = await server.handle(post(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"\#(version)"}}"#))
    return response.headers["Mcp-Session-Id"] ?? ""
}

@Suite struct McpServerTests {
    @Test func initializeNegotiatesVersionAndIssuesSession() async {
        let server = makeServer()
        for (asked, expected) in [("2025-11-25", "2025-11-25"), ("2025-06-18", "2025-06-18"), ("2099-01-01", "2025-11-25")] {
            let response = await server.handle(post(#"{"jsonrpc":"2.0","id":7,"method":"initialize","params":{"protocolVersion":"\#(asked)"}}"#))
            #expect(response.status == 200)
            #expect(response.headers["Content-Type"] == "application/json")
            #expect(response.headers["Mcp-Session-Id"]?.isEmpty == false)
            let result = body(response)["result"]
            #expect(result?["protocolVersion"] == .string(expected))
            #expect(result?["serverInfo"]?["name"] == "xdesk")
            #expect(result?["capabilities"]?["tools"] != nil)
            #expect(body(response)["id"] == 7)
        }
    }

    @Test func initializeWithoutVersionIsInvalidParams() async {
        let response = await makeServer().handle(post(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#))
        #expect(body(response)["error"]?["code"] == .int(JsonRpcErrorCode.invalidParams))
    }

    @Test func requestsNeedValidSession() async {
        let server = makeServer()
        let list = #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#
        #expect(await server.handle(post(list)).status == 400)
        #expect(await server.handle(post(list, session: "unknown")).status == 404)
        let session = await openSession(server)
        #expect(await server.handle(post(list, session: session)).status == 200)
    }

    @Test func notificationsReturn202AndNeedSession() async {
        let server = makeServer()
        let note = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        #expect(await server.handle(post(note)).status == 400)
        let session = await openSession(server)
        let response = await server.handle(post(note, session: session))
        #expect(response.status == 202)
        #expect(response.body.isEmpty)
    }

    @Test func pingReturnsEmptyResult() async {
        let server = makeServer()
        let session = await openSession(server)
        let response = await server.handle(post(#"{"jsonrpc":"2.0","id":"p","method":"ping"}"#, session: session))
        #expect(body(response)["result"] == [:])
        #expect(body(response)["id"] == "p")
    }

    @Test func toolsListHasFourteenToolsWithSchemasAndAnnotations() async {
        let server = makeServer()
        let session = await openSession(server)
        let response = await server.handle(post(#"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#, session: session))
        guard case .array(let tools)? = body(response)["result"]?["tools"] else { Issue.record("thiếu tools"); return }
        #expect(tools.count == 15)
        #expect(Set(tools.compactMap { $0["name"]?.stringValue }).count == 15)
        for tool in tools {
            #expect(tool["inputSchema"]?["type"] == "object")
            #expect(tool["annotations"]?["readOnlyHint"] != nil)
            #expect(tool["annotations"]?["destructiveHint"] != nil)
        }
        let status = tools.first { $0["name"] == "xdesk_status" }
        #expect(status?["annotations"]?["readOnlyHint"] == true)
        let pointer = tools.first { $0["name"] == "xdesk_pointer" }
        #expect(pointer?["annotations"]?["destructiveHint"] == true)
    }

    @Test func statusToolReportsHostState() async {
        let server = makeServer()
        let session = await openSession(server)
        let call = #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"xdesk_status"}}"#
        let result = body(await server.handle(post(call, session: session)))["result"]
        #expect(result?["isError"] == false)
        guard case .array(let content)? = result?["content"], let text = content.first?["text"]?.stringValue else { Issue.record("thiếu content"); return }
        #expect(text.contains("Chia sẻ màn hình: đang bật"))
        #expect(text.contains("Viewer đang xem: 2"))
        #expect(text.contains("Mã hoá: bật"))
        #expect(text.contains("Màn hình agent: chưa có"))
        #expect(text.contains("Người giữ quyền điều khiển: không có"))
    }

    @Test func otherToolsReturnUnsupportedAsToolError() async {
        let server = makeServer()
        let session = await openSession(server)
        let call = #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"xdesk_screenshot","arguments":{}}}"#
        let response = await server.handle(post(call, session: session))
        #expect(response.status == 200)
        #expect(body(response)["error"] == nil)
        #expect(body(response)["result"]?["isError"] == true)
        guard case .array(let content)? = body(response)["result"]?["content"] else { Issue.record("thiếu content"); return }
        #expect(content.first?["text"] == "Chưa hỗ trợ ở bản này (phase 08b)")
    }

    @Test func unknownToolAndMalformedCallAreInvalidParams() async {
        let server = makeServer()
        let session = await openSession(server)
        for call in [
            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"nope"}}"#,
            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{}}"#,
            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"xdesk_status","arguments":[]}}"#,
        ] {
            let response = await server.handle(post(call, session: session))
            #expect(body(response)["error"]?["code"] == .int(JsonRpcErrorCode.invalidParams))
        }
    }

    @Test func unknownMethodIsMethodNotFound() async {
        let server = makeServer()
        let session = await openSession(server)
        let response = await server.handle(post(#"{"jsonrpc":"2.0","id":9,"method":"resources/list"}"#, session: session))
        #expect(body(response)["error"]?["code"] == .int(JsonRpcErrorCode.methodNotFound))
        #expect(body(response)["id"] == 9)
    }

    @Test func parseErrorBatchAndInvalidRequests() async {
        let server = makeServer()
        let parse = await server.handle(post("{not json"))
        #expect(parse.status == 400)
        #expect(body(parse)["error"]?["code"] == .int(JsonRpcErrorCode.parseError))
        let batch = await server.handle(post(#"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#))
        #expect(body(batch)["error"]?["code"] == .int(JsonRpcErrorCode.invalidRequest))
        let noVersion = await server.handle(post(#"{"id":1,"method":"ping"}"#))
        #expect(body(noVersion)["error"]?["code"] == .int(JsonRpcErrorCode.invalidRequest))
        let nullId = await server.handle(post(#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#))
        #expect(body(nullId)["error"]?["code"] == .int(JsonRpcErrorCode.invalidRequest))
    }

    @Test func protocolVersionHeaderIsValidated() async {
        let server = makeServer()
        let ping = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
        let session = await openSession(server)
        #expect(await server.handle(post(ping, session: session, extra: ["mcp-protocol-version": "1999-01-01"])).status == 400)
        #expect(await server.handle(post(ping, session: session, extra: ["mcp-protocol-version": "2025-06-18"])).status == 200)
    }

    @Test func getIs405AndUnknownPathIs404AndDeleteEndsSession() async {
        let server = makeServer()
        var get = post("")
        get.method = "GET"
        let response = await server.handle(get)
        #expect(response.status == 405)
        #expect(response.headers["Allow"] == "POST, DELETE")
        var other = post("")
        other.path = "/other"
        #expect(await server.handle(other).status == 404)

        let session = await openSession(server)
        var delete = post("", session: session)
        delete.method = "DELETE"
        #expect(await server.handle(delete).status == 204)
        #expect(await server.handle(post(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, session: session)).status == 404)
    }

    @Test func guardRunsBeforeRouting() async {
        let server = makeServer()
        var evil = post(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#)
        evil.headers["host"] = "evil.com"
        #expect(await server.handle(evil).status == 403)
        var noToken = post(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#)
        noToken.headers["authorization"] = nil
        #expect(await server.handle(noToken).status == 401)
        var origin = post(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#)
        origin.headers["origin"] = "http://evil.com"
        #expect(await server.handle(origin).status == 403)
    }

    @Test func sessionStoreEvictsOldestBeyondCapacity() {
        let store = McpSessionStore(capacity: 2)
        let first = store.create(version: "2025-11-25")
        _ = store.create(version: "2025-11-25")
        _ = store.create(version: "2025-11-25")
        #expect(!store.contains(first))
    }
}
