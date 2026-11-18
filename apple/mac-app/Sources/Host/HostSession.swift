import Foundation
import os
import XdeskMedia
import XdeskTransport
import XdeskWire

enum HostSessionState: Sendable, Equatable {
    case handshaking
    case streaming(mode: DisplayMode, width: Int, height: Int)
    case ended(String)
}

/// Một viewer: handshake → màn hình ảo → capture → encode → UDP, cộng vòng điều khiển
/// (keyframe.request, net.report → bitrate, ping/pong). Mọi tài nguyên được giải phóng khi `run()` trở về.
actor HostSession {
    static let streamId: UInt16 = 1
    static let initialBitrateKbps = 10_000

    private let connection: ControlConnection
    private let provider: VirtualDisplayProvider
    private let hostCaps: Capabilities
    private let report: @Sendable (HostSessionState) -> Void
    private let log = Logger(subsystem: "vn.xox.xdesk", category: "host-session")
    private var channel: UdpMediaChannel?
    private var pipeline: HostPipeline?
    private var bitrate = BitrateController(initialKbps: HostSession.initialBitrateKbps)
    private var tasks: [Task<Void, Never>] = []

    init(
        connection: ControlConnection, provider: VirtualDisplayProvider, caps: Capabilities,
        report: @escaping @Sendable (HostSessionState) -> Void
    ) {
        self.connection = connection
        self.provider = provider
        self.hostCaps = caps
        self.report = report
    }

    func run() async {
        report(.handshaking)
        var reason = "viewer ngắt kết nối"
        do {
            let result = try await connection.performHostHandshake(caps: hostCaps, sessionId: UUID().uuidString) { [self] _, display in
                try await prepare(display)
            }
            try await startPipeline(result.display)
            try await controlLoop()
        } catch {
            reason = error.localizedDescription
            log.error("session ended: \(reason, privacy: .public)")
        }
        await teardown()
        report(.ended(reason))
    }

    /// Đóng kết nối điều khiển → `run()` thoát và dọn dẹp.
    func shutdown() async { await connection.close() }

    // MARK: Chuẩn bị (trong handshake)

    private func prepare(_ display: DisplayConfig) async throws -> DisplayReady {
        let channel = try await UdpMediaChannel.listen(streamId: Self.streamId, allowedPeerHost: connection.remoteHost)
        self.channel = channel
        return DisplayReady(udpPort: await channel.localPort, streamId: Self.streamId)
    }

    private func startPipeline(_ config: DisplayConfig) async throws {
        guard let channel else { throw TransportError.noPeer }
        let width = Int(config.w), height = Int(config.h)
        let hiDPI = config.scale >= 2
        let acquired = await provider.acquire(VirtualDisplaySpec(
            pixelWidth: width, pixelHeight: height, refreshRate: Double(config.fps), hiDPI: hiDPI
        ))
        if let reason = acquired.fallbackReason { log.notice("fallback \(acquired.mode == .mirror ? "mirror" : "extend", privacy: .public): \(reason, privacy: .public)") }
        let settings = EncoderSettings(width: width, height: height, fps: Int(config.fps), bitrateKbps: Self.initialBitrateKbps, codec: config.codec)
        let pipeline = try HostPipeline(displayID: acquired.displayID, settings: settings) { [connection] error in
            Task { _ = try? await connection.send(.bye(Bye(reason: error?.localizedDescription ?? "capture stopped"))); await connection.close() }
        }
        self.pipeline = pipeline
        try await pipeline.start()
        tasks.append(Task { await Self.pumpFrames(pipeline.encoder, to: channel) })
        tasks.append(Task { [weak pipeline] in
            for await event in channel.events {
                if case .peerConnected = event { pipeline?.beginStreaming() }
            }
        })
        report(.streaming(mode: acquired.mode, width: width, height: height))
    }

    private static func pumpFrames(_ encoder: VideoEncoder, to channel: UdpMediaChannel) async {
        var frameNo: UInt32 = 0
        do {
            for try await frame in encoder.frames {
                try await channel.sendFrame(frame.data, frameNo: frameNo, ptsMs: frame.ptsMs, isKeyframe: frame.isKeyframe)
                frameNo &+= 1
            }
        } catch {
            Logger(subsystem: "vn.xox.xdesk", category: "host-session").error("frame pump stopped: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Vòng điều khiển

    private func controlLoop() async throws {
        while let inbound = try await connection.nextInbound() {
            guard case .message(let envelope) = inbound else { continue }
            switch envelope.message {
            case .keyframeRequest: pipeline?.requestKeyframe()
            case .netReport(let r): try await applyNetReport(r)
            case .ping(let ping):
                let t1 = ClockSync.wallClockMs()
                let pong = ClockSync.makePong(for: ping, receivedAtMs: t1, sentAtMs: ClockSync.wallClockMs())
                _ = try await connection.send(.pong(pong), id: envelope.id)
            case .bye: return
            default: break
            }
        }
    }

    private func applyNetReport(_ r: NetReport) async throws {
        let now = Int(ProcessInfo.processInfo.systemUptime * 1000)
        guard let kbps = bitrate.update(lossPermille: Int(r.lossPermille), rttMs: Int(r.rttMs), nowMs: now) else { return }
        try pipeline?.encoder.setBitrate(kbps: kbps)
        _ = try await connection.send(.bitrateSet(BitrateSet(kbps: UInt32(kbps))))
    }

    // MARK: Dọn dẹp

    private func teardown() async {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        await pipeline?.stop()
        pipeline = nil
        await channel?.close()
        channel = nil
        await connection.close()
        await provider.release()
    }
}
