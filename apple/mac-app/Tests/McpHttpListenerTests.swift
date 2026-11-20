import Foundation
import Testing
import XdeskAgent
@testable import Xdesk

/// Listener thật trên 127.0.0.1: yêu cầu xử lý lâu hơn hạn gửi yêu cầu vẫn phải nhận được kết quả
/// (trước đây mọi kết nối bị cắt sau 10 giây, làm mất kết quả `xdesk_request_control` khi người duyệt chậm).
@Suite(.serialized) struct McpHttpListenerTests {
    private static let token = "listener-test-token"

    private func makeServer(port: UInt16, toolDelay: Duration) -> McpServer {
        let status = StatusTool(snapshot: {
            try? await Task.sleep(for: toolDelay)
            return HostSnapshot(isSharing: true, viewerCount: 0, encryptionOn: true)
        })
        return McpServer(
            requestGuard: RequestGuard(port: port, token: { Self.token }),
            registry: ToolRegistry(handlers: ["xdesk_status": status]),
            serverVersion: "0.0.0-test")
    }

    private func post(_ json: String, port: UInt16, session: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: try #require(URL(string: "http://127.0.0.1:\(port)/mcp")))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer \(Self.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let session { request.setValue(session, forHTTPHeaderField: "Mcp-Session-Id") }
        request.httpBody = Data(json.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, try #require(response as? HTTPURLResponse))
    }

    @Test(.timeLimit(.minutes(1))) func slowToolStillAnswersAfterTheRequestTimeout() async throws {
        let port = UInt16.random(in: 49_200...49_900)
        let listener = McpHttpListener(requestTimeout: .milliseconds(300), responseTimeout: .seconds(5))
        try await listener.start(port: port, server: makeServer(port: port, toolDelay: .seconds(1)))
        defer { listener.stop() }

        let (_, initResponse) = try await post(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}"#, port: port)
        let session = try #require(initResponse.value(forHTTPHeaderField: "Mcp-Session-Id"))
        let (data, response) = try await post(
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"xdesk_status"}}"#, port: port, session: session)
        #expect(response.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self).contains("Chia sẻ màn hình: đang bật"))
    }

    @Test(.timeLimit(.minutes(1))) func responseTimeoutStillCutsOffAHungTool() async throws {
        let port = UInt16.random(in: 49_200...49_900)
        let listener = McpHttpListener(requestTimeout: .milliseconds(300), responseTimeout: .milliseconds(500))
        try await listener.start(port: port, server: makeServer(port: port, toolDelay: .seconds(3)))
        defer { listener.stop() }

        let (_, initResponse) = try await post(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}"#, port: port)
        let session = try #require(initResponse.value(forHTTPHeaderField: "Mcp-Session-Id"))
        await #expect(throws: (any Error).self) {
            _ = try await post(
                #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"xdesk_status"}}"#, port: port, session: session)
        }
    }
}
