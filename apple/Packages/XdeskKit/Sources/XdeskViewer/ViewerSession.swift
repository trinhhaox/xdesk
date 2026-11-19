import CoreMedia
import Foundation
import Network
import Observation
import os
import XdeskCrypto
import XdeskInput
import XdeskMedia
import XdeskTransport
import XdeskWire

/// Phía viewer của một kết nối: handshake → UDP → giải khung → `VideoLayerRenderer`,
/// cộng ping/pong (ClockSync), `net.report` mỗi 500 ms và `keyframe.request` khi cần.
/// Dùng lại được: sau `disconnect()` hoặc lỗi có thể `connect` lại (renderer giữ nguyên để view không phải dựng lại).
@MainActor
@Observable
public final class ViewerSession {
    public enum State: Equatable, Sendable {
        case idle
        case connecting
        case streaming
        case failed(String)
    }

    static let keyframeRequestMinGapMs = 500

    public private(set) var state: State = .idle
    public private(set) var fps = 0
    public private(set) var recvKbps = 0
    public private(set) var rttMs: Int64?
    /// Đích đã kết nối thành công (QR có thể thử nhiều địa chỉ); phiên mở lại dùng đích này.
    public private(set) var connectedTarget: ViewerTarget?
    /// Chênh đồng hồ host − viewer (ms); dùng cho overlay đo độ trễ.
    public private(set) var clockOffsetMs: Double?
    /// Host đã ghép vừa từ chối IK ở lần `connect` gần nhất (id = fingerprint); UI đề nghị ghép đôi lại.
    public internal(set) var refusedHostId: String?
    /// Fingerprint host của phiên hiện tại (đặt sau khi bắt tay mã hoá thành công).
    @ObservationIgnored var connectedHostId: String?
    /// Yêu cầu duyệt quyền điều khiển cho agent AI đang chờ trả lời (xem `agent.approve`); nil khi không có/đã hết hạn.
    public internal(set) var pendingAgentApproval: AgentApprovalRequest?
    public let renderer = VideoLayerRenderer()

    @ObservationIgnored let log = Logger(subsystem: "vn.xox.xdesk", category: "viewer-session")
    @ObservationIgnored let security: TransportSecurity
    @ObservationIgnored let deviceName: String
    @ObservationIgnored let trust: ViewerTrust?
    @ObservationIgnored var connection: ControlConnection?
    @ObservationIgnored var channel: UdpMediaChannel?
    @ObservationIgnored var tasks: [Task<Void, Never>] = []
    @ObservationIgnored var factory = SampleBufferFactory(codec: .h264)
    @ObservationIgnored var clock = ClockSync()
    @ObservationIgnored var stats = ViewerStats()
    @ObservationIgnored var lastKeyframeRequestMs = 0
    @ObservationIgnored var streamId: UInt16 = 0
    @ObservationIgnored var inputSequencer = InputSequencer()
    @ObservationIgnored var inputOutbox: AsyncStream<MediaPacket>.Continuation?
    @ObservationIgnored var lastHeartbeatMs: Int64 = 0
    #if DEBUG
    @ObservationIgnored var windowCount = 0
    #endif

    /// `trust` bắt buộc khi `security == .encrypted` (danh tính + host đã biết); plaintext (Debug) bỏ qua.
    public init(security: TransportSecurity, deviceName: String, trust: ViewerTrust? = nil) {
        self.security = security
        self.deviceName = deviceName
        self.trust = trust
    }

    /// Giờ host ước lượng cho thời điểm hiện tại của viewer (nil khi chưa đồng bộ).
    public func hostNowMs() -> Int64? { clock.viewerToHostMs(ClockSync.wallClockMs()) }

    public func connect(to target: ViewerTarget, config: DisplayConfig, auth: ViewerAuth = .automatic) async {
        await connect(candidates: [target], config: config, auth: auth)
    }

    func connect(candidates: [ViewerTarget], config: DisplayConfig, auth: ViewerAuth) async {
        guard state == .idle || isFailed else { return }
        state = .connecting
        refusedHostId = nil
        connectedHostId = nil
        do {
            try await establish(candidates, config: config, auth: auth)
            state = .streaming
        } catch {
            log.error("connect failed: \(error.localizedDescription, privacy: .public)")
            await teardown()
            state = .failed(error.localizedDescription)
        }
    }

    public func disconnect() async {
        if let connection { _ = try? await connection.send(.bye(Bye(reason: "viewer closed"))) }
        await teardown()
        state = .idle
    }

    private var isFailed: Bool { if case .failed = state { true } else { false } }

    // MARK: Kết nối

    private func establish(_ candidates: [ViewerTarget], config: DisplayConfig, auth: ViewerAuth) async throws {
        let (conn, target) = try await openConnection(candidates)
        connectedTarget = target
        connection = conn
        try await authenticate(conn, target: target, auth: auth)
        let result = try await conn.performViewerHandshake(name: deviceName, caps: [.h264, .hevc], display: config)
        guard let host = await conn.resolvedRemoteHost else { throw TransportError.connectionFailed("không xác định được địa chỉ host") }
        factory = SampleBufferFactory(codec: config.codec)
        streamId = result.ready.streamId
        let channel = try await UdpMediaChannel.connect(streamId: streamId, host: host, port: result.ready.udpPort, keys: await conn.udpKeys)
        self.channel = channel
        await wireResync(channel: channel, connection: conn)
        let (packets, outbox) = AsyncStream.makeStream(of: MediaPacket.self)
        inputOutbox = outbox
        tasks = [
            Task { [weak self] in await self?.pumpInput(packets, to: channel) },
            Task { [weak self] in await self?.inputMaintenanceLoop() },
            Task { [weak self] in await self?.readControl(conn) },
            Task { [weak self] in await self?.consume(channel.events) },
            Task { [weak self] in await self?.pingLoop(conn) },
            Task { [weak self] in await self?.reportLoop() },
        ]
    }

    func setState(_ newState: State) { state = newState }

    func updateClock(_ sample: ClockSample) {
        clock.add(sample)
        rttMs = clock.rttMs
        clockOffsetMs = clock.offsetMs
    }

    func updateRates(fps: Int, recvKbps: Int) {
        self.fps = fps
        self.recvKbps = recvKbps
    }

    /// Phiên hỏng giữa chừng (host đóng, thu hồi, mất UDP): báo `failed` rồi dừng mọi vòng lặp; UI gọi `disconnect()` để về `idle`.
    func fail(_ message: String) async {
        guard state == .streaming else { return }
        setState(.failed(message))
        await teardown()
    }

    func teardown() async {
        pendingAgentApproval = nil
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        inputOutbox?.finish()
        inputOutbox = nil
        inputSequencer = InputSequencer()
        await channel?.close()
        channel = nil
        await connection?.close()
        connection = nil
        renderer.flush()
        clock = ClockSync()
        stats = ViewerStats()
        fps = 0
        recvKbps = 0
        rttMs = nil
        clockOffsetMs = nil
    }
}
