import CoreMedia
import Foundation
import Network
import Observation
import os
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
    /// Chênh đồng hồ host − viewer (ms); dùng cho overlay đo độ trễ.
    public private(set) var clockOffsetMs: Double?
    public let renderer = VideoLayerRenderer()

    @ObservationIgnored let log = Logger(subsystem: "vn.xox.xdesk", category: "viewer-session")
    @ObservationIgnored let security: TransportSecurity
    @ObservationIgnored let deviceName: String
    @ObservationIgnored var connection: ControlConnection?
    @ObservationIgnored var channel: UdpMediaChannel?
    @ObservationIgnored var tasks: [Task<Void, Never>] = []
    @ObservationIgnored var factory = SampleBufferFactory(codec: .h264)
    @ObservationIgnored var clock = ClockSync()
    @ObservationIgnored var stats = ViewerStats()
    @ObservationIgnored var lastKeyframeRequestMs = 0
    @ObservationIgnored var streamId: UInt16 = 0
    #if DEBUG
    @ObservationIgnored var windowCount = 0
    #endif

    public init(security: TransportSecurity, deviceName: String) {
        self.security = security
        self.deviceName = deviceName
    }

    /// Giờ host ước lượng cho thời điểm hiện tại của viewer (nil khi chưa đồng bộ).
    public func hostNowMs() -> Int64? { clock.viewerToHostMs(ClockSync.wallClockMs()) }

    public func connect(to target: ViewerTarget, config: DisplayConfig) async {
        guard state == .idle || isFailed else { return }
        state = .connecting
        do {
            try await establish(target, config: config)
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

    private func establish(_ target: ViewerTarget, config: DisplayConfig) async throws {
        let conn: ControlConnection
        switch target {
        case .discovered(let host): conn = try await ControlConnection.connect(to: host.endpoint, security: security)
        case .manual(let host, let port): conn = try await ControlConnection.connect(host: host, port: port, security: security)
        }
        connection = conn
        let result = try await conn.performViewerHandshake(name: deviceName, caps: [.h264, .hevc], display: config)
        guard let host = await conn.resolvedRemoteHost else { throw TransportError.connectionFailed("không xác định được địa chỉ host") }
        factory = SampleBufferFactory(codec: config.codec)
        streamId = result.ready.streamId
        let channel = try await UdpMediaChannel.connect(streamId: streamId, host: host, port: result.ready.udpPort)
        self.channel = channel
        tasks = [
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

    private func teardown() async {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
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
