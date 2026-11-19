import Foundation

/// Toàn bộ logic HTTP + JSON-RPC của endpoint `/mcp` (không đụng socket nên test được hoàn toàn).
public final class McpServer: Sendable {
    public static let endpointPath = "/mcp"

    private let requestGuard: RequestGuard
    private let registry: ToolRegistry
    private let sessions: McpSessionStore
    private let audit: AuditLog?
    private let serverVersion: String
    private let onClientName: (@Sendable (String) -> Void)?

    /// `onClientName` nhận `clientInfo.name` của agent khi initialize, để hộp thoại duyệt hiện đúng tên (Claude Code, Cursor…).
    public init(
        requestGuard: RequestGuard, registry: ToolRegistry, sessions: McpSessionStore = McpSessionStore(),
        audit: AuditLog? = nil, serverVersion: String, onClientName: (@Sendable (String) -> Void)? = nil
    ) {
        self.onClientName = onClientName
        self.requestGuard = requestGuard
        self.registry = registry
        self.sessions = sessions
        self.audit = audit
        self.serverVersion = serverVersion
    }

    public func handle(_ request: HttpRequest) async -> HttpResponse {
        let started = ContinuousClock.now
        let outcome = await route(request)
        let elapsed = ContinuousClock.now - started
        let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        audit?.record(method: outcome.method, tool: outcome.tool, result: outcome.result, durationMs: ms, detail: outcome.detail)
        return outcome.response
    }

    private struct Outcome {
        var response: HttpResponse
        var method = "-"
        var tool: String?
        var result: String
        var detail: String?

        init(_ response: HttpResponse, method: String = "-", tool: String? = nil, result: String? = nil, detail: String? = nil) {
            self.detail = detail
            self.response = response
            self.method = method
            self.tool = tool
            self.result = result ?? (response.status < 400 ? "ok" : "http_\(response.status)")
        }
    }

    private func route(_ request: HttpRequest) async -> Outcome {
        if case .reject(let status, let message, let retryAfter) = requestGuard.evaluate(headers: request.headers) {
            let headers = retryAfter.map { ["Retry-After": String($0)] } ?? [:]
            return Outcome(.failure(status: status, message: message, headers: headers), method: "guard")
        }
        guard request.path == Self.endpointPath else { return Outcome(.failure(status: 404, message: "Không có đường dẫn này")) }
        switch request.method {
        case "POST": return await handlePost(request)
        case "DELETE": return terminate(request)
        default: return Outcome(.failure(status: 405, message: "Chỉ hỗ trợ POST", headers: ["Allow": "POST, DELETE"]), method: request.method)
        }
    }

    private func terminate(_ request: HttpRequest) -> Outcome {
        if let failure = sessionFailure(request) { return Outcome(failure, method: "DELETE") }
        if let id = request.headers[McpProtocol.sessionHeader.lowercased()] { sessions.remove(id) }
        return Outcome(.empty(status: 204), method: "DELETE")
    }

    private func handlePost(_ request: HttpRequest) async -> Outcome {
        if let version = request.headers["mcp-protocol-version"], !McpProtocol.supported.contains(version) {
            return Outcome(.failure(status: 400, message: "Phiên bản giao thức không hỗ trợ: \(version)"), method: "POST")
        }
        switch JsonRpcMessage.parse(request.body) {
        case .parseError:
            return rpcError(nil, JsonRpcErrorCode.parseError, "JSON không hợp lệ", status: 400)
        case .batch:
            return rpcError(nil, JsonRpcErrorCode.invalidRequest, "Không hỗ trợ batch JSON-RPC (đã bỏ từ MCP 2025-06-18)", status: 400)
        case .invalid(let reason):
            return rpcError(nil, JsonRpcErrorCode.invalidRequest, reason, status: 400)
        case .notification(let method):
            if let failure = sessionFailure(request) { return Outcome(failure, method: method) }
            return Outcome(.empty(status: 202), method: method)
        case .response:
            if let failure = sessionFailure(request) { return Outcome(failure, method: "response") }
            return Outcome(.empty(status: 202), method: "response")
        case .request(let id, let method, let params):
            if method == "initialize" { return initialize(id: id, params: params) }
            if let failure = sessionFailure(request) { return Outcome(failure, method: method) }
            return await dispatch(id: id, method: method, params: params)
        }
    }

    private func initialize(id: JsonValue, params: JsonValue) -> Outcome {
        guard let requested = params["protocolVersion"]?.stringValue else {
            return rpcError(id, JsonRpcErrorCode.invalidParams, "Thiếu protocolVersion", method: "initialize")
        }
        if let name = params["clientInfo"]?["name"]?.stringValue { onClientName?(String(name.prefix(64))) }
        let version = McpProtocol.negotiate(requested)
        let session = sessions.create(version: version)
        let body = JsonRpcResponse.result(id: id, McpProtocol.initializeResult(version: version, serverVersion: serverVersion))
        return Outcome(.json(body, headers: [McpProtocol.sessionHeader: session]), method: "initialize")
    }

    private func dispatch(id: JsonValue, method: String, params: JsonValue) async -> Outcome {
        switch method {
        case "ping": return Outcome(.json(JsonRpcResponse.result(id: id, [:])), method: method)
        case "tools/list": return Outcome(.json(JsonRpcResponse.result(id: id, registry.listResult)), method: method)
        case "tools/call": return await callTool(id: id, params: params)
        default: return rpcError(id, JsonRpcErrorCode.methodNotFound, "Không hỗ trợ method: \(method)", method: method)
        }
    }

    private func callTool(id: JsonValue, params: JsonValue) async -> Outcome {
        guard let name = params["name"]?.stringValue else {
            return rpcError(id, JsonRpcErrorCode.invalidParams, "Thiếu tên tool", method: "tools/call")
        }
        let arguments = params["arguments"] ?? [:]
        guard arguments.objectValue != nil else {
            return rpcError(id, JsonRpcErrorCode.invalidParams, "arguments phải là object", method: "tools/call", tool: name)
        }
        guard let result = await registry.call(name: name, arguments: arguments) else {
            return rpcError(id, JsonRpcErrorCode.invalidParams, "Không có tool: \(name)", method: "tools/call")
        }
        return Outcome(.json(JsonRpcResponse.result(id: id, result.json)), method: "tools/call", tool: name, result: result.isError ? "tool_error" : "ok", detail: result.audit)
    }

    /// Thiếu header phiên → 400, phiên không tồn tại (hết hạn/đã đóng) → 404 để client khởi tạo lại.
    private func sessionFailure(_ request: HttpRequest) -> HttpResponse? {
        guard let id = request.headers[McpProtocol.sessionHeader.lowercased()] else {
            return .failure(status: 400, message: "Thiếu header Mcp-Session-Id")
        }
        return sessions.contains(id) ? nil : .failure(status: 404, message: "Phiên không tồn tại, hãy gọi initialize lại")
    }

    private func rpcError(
        _ id: JsonValue?, _ code: Int, _ message: String, status: Int = 200, method: String = "POST", tool: String? = nil
    ) -> Outcome {
        Outcome(.json(JsonRpcResponse.error(id: id, code: code, message: message), status: status), method: method, tool: tool, result: "rpc_error_\(code)")
    }
}
