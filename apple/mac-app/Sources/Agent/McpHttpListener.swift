import Foundation
import Network
import os
import XdeskAgent

enum McpListenerError: Error, CustomStringConvertible {
    case failed(String)
    var description: String { if case .failed(let message) = self { message } else { "" } }
}

/// Máy chủ HTTP/1.1 tối thiểu trên NWListener, CHỈ bind 127.0.0.1. Mỗi kết nối phục vụ một yêu cầu rồi đóng.
/// Trạng thái `slots` chỉ đụng trong `queue`, nên an toàn khi đánh dấu `@unchecked Sendable`.
final class McpHttpListener: @unchecked Sendable {
    /// Thời gian tối đa để client gửi xong một yêu cầu (chặn kết nối treo/gửi rỉ rả).
    private let requestTimeout: DispatchTimeInterval
    /// Thời gian tối đa để trả lời một yêu cầu đã nhận đủ. Phải dài hơn thời gian chờ người duyệt
    /// (`ControlArbiter`, mặc định 60 giây) để `xdesk_request_control` không mất kết quả.
    private let responseTimeout: DispatchTimeInterval

    init(requestTimeout: DispatchTimeInterval = .seconds(10), responseTimeout: DispatchTimeInterval = .seconds(120)) {
        self.requestTimeout = requestTimeout
        self.responseTimeout = responseTimeout
    }

    private let log = Logger(subsystem: "vn.xox.xdesk", category: "mcp-listener")
    private let queue = DispatchQueue(label: "vn.xox.xdesk.mcp-listener")
    private var listener: NWListener?
    private var slots = McpConnectionSlots(limit: 32)

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
        guard let slot = slots.acquire() else { connection.cancel(); return }
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed: self?.slots.release(slot)
            default: break
            }
        }
        connection.start(queue: queue)
        let progress = RequestProgress()
        queue.asyncAfter(deadline: .now() + self.requestTimeout) {
            if !progress.received { connection.cancel() }
        }
        receive(on: connection, buffer: Data(), server: server, progress: progress)
    }

    /// Đã nhận đủ yêu cầu thì chuyển sang hạn trả lời dài hơn.
    private func requestReceived(on connection: NWConnection, progress: RequestProgress) {
        progress.received = true
        queue.asyncAfter(deadline: .now() + self.responseTimeout) { connection.cancel() }
    }

    private func receive(on connection: NWConnection, buffer: Data, server: McpServer, progress: RequestProgress) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HttpRequestParser.parse(buffer) {
            case .needMore:
                if error != nil || isComplete {
                    connection.cancel()
                } else {
                    receive(on: connection, buffer: buffer, server: server, progress: progress)
                }
            case .failure(let status, let message):
                requestReceived(on: connection, progress: progress)
                send(.failure(status: status, message: message), on: connection)
            case .request(let request, _):
                requestReceived(on: connection, progress: progress)
                Task { send(await server.handle(request), on: connection) }
            }
        }
    }

    private func send(_ response: HttpResponse, on connection: NWConnection) {
        connection.send(content: response.serialized(), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
    }
}

/// Một kết nối đã nhận đủ yêu cầu chưa; chỉ đụng trong `queue` của listener.
private final class RequestProgress: @unchecked Sendable {
    var received = false
}
