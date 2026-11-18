import Foundation
import Network
import XdeskWire

/// Thứ nhận được trên kênh điều khiển (sau giải khung).
public enum ControlInbound: Sendable, Equatable {
    case message(ControlEnvelope)
    /// Gói media gửi dự phòng qua TCP (kind 0x04).
    case mediaOverTcp(MediaPacket)
    case bulk([UInt8])
    case handshake([UInt8])
}

/// Kết nối điều khiển TCP: framing của XdeskWire, mỗi frame một message. Lỗi giải khung/JSON → đóng kết nối.
/// Chỉ MỘT task được gọi `nextInbound()` tại một thời điểm.
public actor ControlConnection {
    public nonisolated let remoteEndpoint: NWEndpoint
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "xdesk.control.connection")
    private var decoder = ControlFrameDecoder()
    private var nextMessageId: UInt32 = 1
    private var closed = false
    private var onClose: (@Sendable () -> Void)?
    var watchdogFired = false

    init(connection: NWConnection, onClose: (@Sendable () -> Void)? = nil) {
        self.connection = connection
        self.remoteEndpoint = connection.endpoint
        self.onClose = onClose
    }

    /// Kết nối tới host (viewer).
    public static func connect(
        to endpoint: NWEndpoint, security: TransportSecurity, timeoutSeconds: Double = 5
    ) async throws -> ControlConnection {
        try security.requireAvailable()
        let conn = ControlConnection(connection: NWConnection(to: endpoint, using: .tcp))
        try await conn.start(timeoutSeconds: timeoutSeconds)
        return conn
    }

    public static func connect(
        host: String, port: UInt16, security: TransportSecurity, timeoutSeconds: Double = 5
    ) async throws -> ControlConnection {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw TransportError.connectionFailed("port 0") }
        return try await connect(to: .hostPort(host: NWEndpoint.Host(host), port: nwPort), security: security, timeoutSeconds: timeoutSeconds)
    }

    func start(timeoutSeconds: Double = 5) async throws {
        do {
            try await startAndAwaitReady(connection, queue: queue, timeoutSeconds: timeoutSeconds)
        } catch {
            close()
            throw error
        }
    }

    // MARK: Gửi

    /// Gửi một message; trả `id` đã dùng (tự tăng nếu không truyền, phản hồi truyền lại `id` của yêu cầu).
    @discardableResult
    public func send(_ message: ControlMessage, id: UInt32? = nil) async throws -> UInt32 {
        let useId = id ?? takeNextId()
        let payload = try ControlMessageCodec.encode(ControlEnvelope(id: useId, message: message))
        try await sendFrame(ControlFrame(kind: .control, payload: payload))
        return useId
    }

    /// Gói media dự phòng qua TCP.
    public func sendMediaOverTcp(_ packet: MediaPacket) async throws {
        try await sendFrame(ControlFrame(kind: .mediaOverTcp, payload: try packet.encode()))
    }

    public func sendFrame(_ frame: ControlFrame) async throws {
        guard !closed else { throw TransportError.connectionClosed }
        let bytes = try ControlFrameCodec.encode(frame)
        try await write(bytes)
    }

    private func takeNextId() -> UInt32 {
        defer { nextMessageId &+= 1 }
        return nextMessageId
    }

    private func write(_ bytes: [UInt8]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            connection.send(content: Data(bytes), completion: .contentProcessed { error in
                if let error { cont.resume(throwing: TransportError.connectionFailed("\(error)")) } else { cont.resume() }
            })
        }
    }

    // MARK: Nhận

    /// Chờ thứ kế tiếp; `nil` khi đối tác đóng sạch. Message `t` lạ được bỏ qua (tương thích tiến).
    public func nextInbound() async throws -> ControlInbound? {
        while true {
            let frame: ControlFrame?
            do {
                frame = try await nextFrame()
            } catch {
                close()
                throw error
            }
            guard let frame else { close(); return nil }
            do {
                switch frame.kind {
                case .control:
                    let envelope = try ControlMessageCodec.decode(frame.payload)
                    if case .unknown = envelope.message { continue }
                    return .message(envelope)
                case .mediaOverTcp: return .mediaOverTcp(try MediaPacket.decode(frame.payload))
                case .bulk: return .bulk(frame.payload)
                case .handshake: return .handshake(frame.payload)
                }
            } catch {
                close()
                throw error
            }
        }
    }

    private func nextFrame() async throws -> ControlFrame? {
        while true {
            if let frame = try decoder.next() { return frame }
            guard let chunk = try await readChunk() else { return nil }
            decoder.append(chunk)
        }
    }

    private func readChunk() async throws -> [UInt8]? {
        while true {
            let chunk: [UInt8]? = try await withCheckedThrowingContinuation { cont in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                    if let error {
                        cont.resume(throwing: TransportError.connectionFailed("\(error)"))
                    } else if let data, !data.isEmpty {
                        cont.resume(returning: [UInt8](data))
                    } else if isComplete {
                        cont.resume(returning: nil)
                    } else {
                        cont.resume(returning: [])
                    }
                }
            }
            if chunk?.isEmpty != true { return chunk }
        }
    }

    // MARK: Đóng

    /// Idempotent. Gọi `onClose` đúng một lần.
    public func close() {
        guard !closed else { return }
        closed = true
        connection.cancel()
        onClose?()
        onClose = nil
    }

    public var isClosed: Bool { closed }
    /// Địa chỉ IP thực của host, kể cả khi đã kết nối bằng Bonjour service endpoint (viewer dùng để mở UDP).
    public var resolvedRemoteHost: NWEndpoint.Host? {
        if case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint ?? remoteEndpoint { return host }
        return nil
    }

    /// Host của đối tác (để giới hạn peer UDP).
    public nonisolated var remoteHost: NWEndpoint.Host? {
        if case .hostPort(let host, _) = remoteEndpoint { return host }
        return nil
    }
}
