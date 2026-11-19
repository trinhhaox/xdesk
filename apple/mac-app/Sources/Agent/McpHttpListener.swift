import Foundation
import Network
import os
import XdeskAgent

enum McpListenerError: Error, CustomStringConvertible {
    case failed(String)
    var description: String { if case .failed(let message) = self { message } else { "" } }
}

/// Máy chủ HTTP/1.1 tối thiểu trên NWListener, CHỈ bind 127.0.0.1. Mỗi kết nối phục vụ một yêu cầu rồi đóng.
/// Trạng thái `activeConnections` chỉ đụng trong `queue`, nên an toàn khi đánh dấu `@unchecked Sendable`.
final class McpHttpListener: @unchecked Sendable {
    private static let maxConnections = 32
    private static let connectionTimeout: DispatchTimeInterval = .seconds(10)

    private let log = Logger(subsystem: "vn.xox.xdesk", category: "mcp-listener")
    private let queue = DispatchQueue(label: "vn.xox.xdesk.mcp-listener")
    private var listener: NWListener?
    private var activeConnections = 0

    func start(port: UInt16, server: McpServer) async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw McpListenerError.failed("Cổng không hợp lệ: \(port)") }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        let nwListener: NWListener
        do { nwListener = try NWListener(using: parameters) } catch { throw McpListenerError.failed("\(error)") }
        nwListener.newConnectionHandler = { [weak self] connection in self?.accept(connection, server: server) }
        try await awaitReady(nwListener)
        listener = nwListener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func awaitReady(_ nwListener: NWListener) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let resumeOnce: @Sendable (Result<Void, McpListenerError>) -> Void = { result in
                guard !resumed.withLock({ let was = $0; $0 = true; return was }) else { return }
                continuation.resume(with: result)
            }
            nwListener.stateUpdateHandler = { [log] state in
                switch state {
                case .ready: resumeOnce(.success(()))
                case .failed(let error): resumeOnce(.failure(.failed("\(error)")))
                case .cancelled: resumeOnce(.failure(.failed("Đã huỷ")))
                default: break
                }
                if case .failed(let error) = state { log.error("MCP listener lỗi: \(String(describing: error), privacy: .public)") }
            }
            nwListener.start(queue: queue)
        }
    }

    private func accept(_ connection: NWConnection, server: McpServer) {
        guard activeConnections < Self.maxConnections else { connection.cancel(); return }
        activeConnections += 1
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed: self?.activeConnections -= 1
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.connectionTimeout) { connection.cancel() }
        receive(on: connection, buffer: Data(), server: server)
    }

    private func receive(on connection: NWConnection, buffer: Data, server: McpServer) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HttpRequestParser.parse(buffer) {
            case .needMore:
                if error != nil || isComplete { connection.cancel() } else { receive(on: connection, buffer: buffer, server: server) }
            case .failure(let status, let message):
                send(.failure(status: status, message: message), on: connection)
            case .request(let request, _):
                Task { send(await server.handle(request), on: connection) }
            }
        }
    }

    private func send(_ response: HttpResponse, on connection: NWConnection) {
        connection.send(content: response.serialized(), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
    }
}
