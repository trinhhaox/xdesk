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
@MainActor
@Observable
final class ViewerSession {
    enum State: Equatable {
        case idle
        case connecting
        case streaming
        case failed(String)
    }

    static let keyframeRequestMinGapMs = 500

    private(set) var state: State = .idle
    private(set) var fps = 0
    private(set) var recvKbps = 0
    private(set) var rttMs: Int64?
    /// Chênh đồng hồ host − viewer (ms); dùng cho overlay đo độ trễ.
    private(set) var clockOffsetMs: Double?
    let renderer = VideoLayerRenderer()

    @ObservationIgnored private let log = Logger(subsystem: "vn.xox.xdesk", category: "viewer-session")
    @ObservationIgnored private var connection: ControlConnection?
    @ObservationIgnored private var channel: UdpMediaChannel?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var factory = SampleBufferFactory(codec: .h264)
    @ObservationIgnored private var clock = ClockSync()
    @ObservationIgnored private var stats = ViewerStats()
    @ObservationIgnored private var lastKeyframeRequestMs = 0
    @ObservationIgnored private var streamId: UInt16 = 0
    #if DEBUG
    @ObservationIgnored private var windowCount = 0
    #endif

    /// Giờ host ước lượng cho thời điểm hiện tại của viewer (nil khi chưa đồng bộ).
    func hostNowMs() -> Int64? { clock.viewerToHostMs(ClockSync.wallClockMs()) }

    func connect(to target: ViewerTarget, config: DisplayConfig) async {
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

    func disconnect() async {
        if let connection { _ = try? await connection.send(.bye(Bye(reason: "viewer closed"))) }
        await teardown()
        state = .idle
    }

    private var isFailed: Bool { if case .failed = state { true } else { false } }

    // MARK: Kết nối

    private func establish(_ target: ViewerTarget, config: DisplayConfig) async throws {
        let conn: ControlConnection
        switch target {
        case .discovered(let host): conn = try await ControlConnection.connect(to: host.endpoint, security: AppSecurity.current)
        case .manual(let host, let port): conn = try await ControlConnection.connect(host: host, port: port, security: AppSecurity.current)
        }
        connection = conn
        let result = try await conn.performViewerHandshake(name: HostIdentity.displayName, caps: [.h264, .hevc], display: config)
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

    // MARK: Điều khiển

    private func readControl(_ conn: ControlConnection) async {
        do {
            while let inbound = try await conn.nextInbound() {
                guard case .message(let envelope) = inbound else { continue }
                switch envelope.message {
                case .pong(let pong): addSample(ClockSample(pong: pong, receivedAtMs: ClockSync.wallClockMs()))
                case .bye(let bye): throw TransportError.rejected(reason: "bye", detail: bye.reason)
                default: break
                }
            }
            if state == .streaming { state = .failed("Host đã ngắt kết nối") }
        } catch {
            if state == .streaming { state = .failed(error.localizedDescription) }
        }
    }

    private func addSample(_ sample: ClockSample) {
        clock.add(sample)
        rttMs = clock.rttMs
        clockOffsetMs = clock.offsetMs
    }

    private func pingLoop(_ conn: ControlConnection) async {
        var interval = 100
        while !Task.isCancelled {
            do { _ = try await conn.send(.ping(Ping(t0: ClockSync.wallClockMs()))) } catch { return }
            try? await Task.sleep(for: .milliseconds(interval))
            interval = min(1000, interval + 100)
        }
    }

    // MARK: Video

    private func consume(_ events: AsyncStream<UdpMediaChannel.Event>) async {
        for await event in events {
            switch event {
            case .frame(let frame): render(frame)
            case .keyframeNeeded: await requestKeyframe()
            case .peerConnected, .packet: break
            }
        }
    }

    private func render(_ frame: AssembledFrame) {
        stats.record(frameNo: frame.frameNo, byteCount: frame.data.count)
        do {
            if let sample = try factory.makeSampleBuffer(annexB: frame.data, ptsMs: frame.ptsMs, isKeyframe: frame.isKeyframe) {
                if !renderer.enqueue(sample) { Task { await requestKeyframe() } }
            } else if !frame.isKeyframe {
                Task { await requestKeyframe() }
            }
        } catch {
            log.error("decode failed: \(error.localizedDescription, privacy: .public)")
            Task { await requestKeyframe() }
        }
    }

    private func requestKeyframe() async {
        let now = Int(ProcessInfo.processInfo.systemUptime * 1000)
        guard now - lastKeyframeRequestMs >= Self.keyframeRequestMinGapMs, let connection else { return }
        lastKeyframeRequestMs = now
        do { _ = try await connection.send(.keyframeRequest(KeyframeRequest(streamId: streamId))) } catch {
            log.error("keyframe.request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func reportLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            await reportNow()
        }
    }

    private func reportNow() async {
        let now = Int(ProcessInfo.processInfo.systemUptime * 1000)
        guard let window = stats.closeWindow(nowMs: now), let connection else { return }
        fps = window.fps
        #if DEBUG
        windowCount += 1
        if windowCount % 4 == 0 {
            log.notice("stats fps=\(window.fps) kbps=\(window.recvKbps) lossPermille=\(window.lossPermille) rttMs=\(self.rttMs ?? -1) offsetMs=\(self.clockOffsetMs ?? .nan)")
        }
        #endif
        recvKbps = window.recvKbps
        let report = NetReport(
            rttMs: UInt32(max(0, rttMs ?? 0)), lossPermille: UInt32(min(1000, window.lossPermille)), jitterMs: 0,
            recvKbps: UInt32(window.recvKbps)
        )
        do { _ = try await connection.send(.netReport(report)) } catch {
            log.error("net.report failed: \(error.localizedDescription, privacy: .public)")
        }
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
    }
}
