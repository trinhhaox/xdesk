import CryptoKit
import Foundation
import Network
import XdeskCrypto
import XdeskWire

/// Thứ nhận được trên kênh điều khiển (sau giải khung).
public enum ControlInbound: Sendable, Equatable {
    case message(ControlEnvelope)
    /// Gói media gửi dự phòng qua TCP (kind 0x04).
    case mediaOverTcp(MediaPacket)
    case bulk([UInt8])
    case handshake([UInt8])
}

/// Khoá UDP của phiên (dẫn xuất từ Noise), đưa cho `UdpMediaChannel`.
public struct UdpKeys: Sendable, Redacted {
    public let send: SymmetricKey
    public let receive: SymmetricKey
}

/// Kết nối điều khiển TCP: framing của XdeskWire, mỗi frame một message. Lỗi giải khung/JSON → đóng kết nối.
/// Chỉ MỘT task được gọi `nextInbound()` tại một thời điểm.
/// Chế độ mã hoá: chỉ nhận frame bắt tay (0x01) tới khi `installSession`, sau đó mọi frame 0x02-0x04 qua `ControlCipher`.
public actor ControlConnection {
    enum Mode { case plaintext, awaitingKeys, secured }

    public nonisolated let remoteEndpoint: NWEndpoint
    let connection: NWConnection
    let queue = DispatchQueue(label: "xdesk.control.connection")
    var decoder = ControlFrameDecoder()
    var nextMessageId: UInt32 = 1
    var closed = false
    var onClose: (@Sendable () -> Void)?
    var watchdogFired = false
    var mode: Mode
    var cipher: ControlCipher?
    var rekeyInterval = ControlCipher.rekeyInterval
    var firstFrameHooks: [@Sendable () async -> Void] = []
    public internal(set) var peer: AuthenticatedPeer?
    public internal(set) var udpKeys: UdpKeys?

    init(connection: NWConnection, encrypted: Bool = false, onClose: (@Sendable () -> Void)? = nil) {
        self.connection = connection
        self.remoteEndpoint = connection.endpoint
        self.onClose = onClose
        self.mode = encrypted ? .awaitingKeys : .plaintext
    }

    /// Kết nối tới host (viewer).
    public static func connect(
        to endpoint: NWEndpoint, security: TransportSecurity, timeoutSeconds: Double = 5
    ) async throws -> ControlConnection {
        try security.requireAvailable()
        let conn = ControlConnection(connection: NWConnection(to: endpoint, using: .tcp), encrypted: security == .encrypted)
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
        try await write(try wireBytes(for: frame))
    }

    private func takeNextId() -> UInt32 {
        defer { nextMessageId &+= 1 }
        return nextMessageId
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
