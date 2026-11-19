import CoreGraphics
import Foundation
import os
import XdeskClipboard
import XdeskCrypto
import XdeskMedia
import XdeskTransport
import XdeskWire

enum HostSessionState: Sendable, Equatable {
    case handshaking
    case streaming(mode: DisplayMode, width: Int, height: Int, info: ViewerSessionInfo)
    case ended(String)
}

/// Một viewer: handshake → màn hình ảo → capture → encode → UDP, cộng vòng điều khiển
/// (keyframe.request, net.report → bitrate, ping/pong). Mọi tài nguyên được giải phóng khi `run()` trở về.
actor HostSession {
    static let streamId: UInt16 = 1
    static let initialBitrateKbps = 10_000

    let connection: ControlConnection
    let provider: VirtualDisplayProvider
    let windowFit: WindowFitter?
    var windowFitActive = false
    let hostCaps: Capabilities
    private let report: @Sendable (HostSessionState) -> Void
    let onSecureInput: @Sendable (Bool) -> Void
    let onAgentAnswer: @Sendable (_ requestId: String, _ allow: Bool) -> Void
    let log = Logger(subsystem: "vn.xox.xdesk", category: "host-session")
    private(set) var channel: UdpMediaChannel?
    var pipeline: HostPipeline?
    var audio: HostAudioStreamer?
    var mutedLocalOutput = false
    let audioSettings: HostAudioSettings
    var input: HostInputService?
    var viewerReady = false
    /// Tên thiết bị viewer tự khai trong Hello (dự phòng khi chưa có peer đã xác thực).
    private var helloName = ""
    /// Quyền của thiết bị đã ghép (plaintext Debug: mặc định). `view` tắt → từ chối phiên; `input` tắt → bỏ input.
    private(set) var permissions = DevicePermissions.default
    var bitrate = BitrateController(initialKbps: HostSession.initialBitrateKbps)
    private var tasks: [Task<Void, Never>] = []
    let pasteboard: (any PasteboardAccess)?
    let permissionLookup: @Sendable ([UInt8]) async -> DevicePermissions?
    var clipboard: ClipboardSync?

    init(
        connection: ControlConnection, provider: VirtualDisplayProvider, windowFit: WindowFitter? = nil, caps: Capabilities,
        report: @escaping @Sendable (HostSessionState) -> Void,
        onSecureInput: @escaping @Sendable (Bool) -> Void = { _ in },
        onAgentAnswer: @escaping @Sendable (String, Bool) -> Void = { _, _ in },
        pasteboard: (any PasteboardAccess)? = nil,
        audioSettings: HostAudioSettings = HostAudioSettings(),
        permissionLookup: @escaping @Sendable ([UInt8]) async -> DevicePermissions? = { _ in nil }
    ) {
        self.audioSettings = audioSettings
        self.pasteboard = pasteboard
        self.permissionLookup = permissionLookup
        self.onAgentAnswer = onAgentAnswer
        self.connection = connection
        self.provider = provider
        self.windowFit = windowFit
        self.hostCaps = caps
        self.report = report
        self.onSecureInput = onSecureInput
    }

    func run() async {
        report(.handshaking)
        var reason = "viewer ngắt kết nối"
        do {
            permissions = await connection.peer?.permissions ?? .default
            let result = try await connection.performHostHandshake(caps: negotiableCaps, sessionId: UUID().uuidString) { [self] hello, display in
                try await prepare(hello, display)
            }
            if result.caps.contains(.clipboard) { await startClipboard() }
            try await startPipeline(result.display, caps: result.caps)
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

    /// Hỏi viewer này có duyệt quyền điều khiển cho agent AI không (chỉ khi đang stream và có quyền input).
    func sendAgentApproval(_ request: AgentApprove) async {
        guard viewerReady, permissions.input else { return }
        do { _ = try await connection.send(.agentApprove(request)) } catch {
            log.error("gửi agent.approve lỗi: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Chuẩn bị (trong handshake)

    private func prepare(_ hello: Hello, _ display: DisplayConfig) async throws -> DisplayReady {
        helloName = hello.name
        permissions = await connection.peer?.permissions ?? .default
        guard permissions.view else { throw TransportError.rejected(reason: "permission", detail: "thiết bị này không có quyền xem") }
        if connection.isUsbTunnel {
            guard Capabilities(rawValue: hello.caps).contains(.mediaOverTcp) else {
                throw TransportError.rejected(reason: "transport", detail: "đường hầm USB cần MediaOverTcp")
            }
            channel = await UdpMediaChannel.overTcp(streamId: Self.streamId, isViewer: false) { [connection] in try await connection.sendMediaOverTcp($0) }
            // Không có UDP: udpPort chỉ là chỗ giữ chỗ (≠ 0 theo spec) và bị viewer bỏ qua khi đã thương lượng MediaOverTcp.
            return DisplayReady(udpPort: 1, streamId: Self.streamId)
        }
        let channel = try await UdpMediaChannel.listen(
            streamId: Self.streamId, allowedPeerHost: connection.remoteHost, keys: await connection.udpKeys)
        self.channel = channel
        await channel.setResyncSink { [connection] resync in
            do { _ = try await connection.send(.rekeyResync(resync)) } catch {
                // Kênh control đã đóng: phiên sắp kết thúc.
            }
        }
        return DisplayReady(udpPort: await channel.localPort, streamId: Self.streamId)
    }

    private func startPipeline(_ config: DisplayConfig, caps: Capabilities) async throws {
        guard let channel else { throw TransportError.noPeer }
        let (acquired, width, height) = try await acquireDisplay(for: config)
        if let reason = acquired.fallbackReason { log.notice("fallback mirror: \(reason, privacy: .public)") }
        log.notice("màn hình \(acquired.mode == .native ? "native" : "ảo", privacy: .public) \(width)x\(height) fit=\(config.fit.rawValue, privacy: .public)")
        let settings = EncoderSettings(width: width, height: height, fps: Int(config.fps), bitrateKbps: Self.initialBitrateKbps, codec: config.codec)
        audio = await makeAudioStreamer(caps: caps, channel: channel)
        let audioSink = audio.map { streamer in { @Sendable (samples: [Int16], captureMs: Double, nowMs: Double) in streamer.ingest(samples: samples, captureMs: captureMs, nowMs: nowMs) } }
        let pipeline = try HostPipeline(displayID: acquired.displayID, settings: settings, audioSink: audioSink) { [connection] error in
            Task { _ = try? await connection.send(.bye(Bye(reason: error?.localizedDescription ?? "capture stopped"))); await connection.close() }
        }
        self.pipeline = pipeline
        try await pipeline.start()
        tasks.append(Task { await Self.pumpFrames(pipeline.encoder, to: channel) })
        await startInput(displayID: acquired.displayID)
        await beginWindowFit(config, displayID: acquired.displayID)
        tasks.append(Task { [weak pipeline] in
            for await event in channel.events {
                switch event {
                case .peerConnected:
                    viewerReady = true
                    audio?.setActive(true)
                    pipeline?.beginStreaming()
                case .packet(let packet): await handleInputPacket(packet)
                case .linkLost: await connection.close()
                default: break
                }
            }
        })
        let peerName = await connection.peer?.name
        let info = ViewerSessionInfo.make(
            name: peerName ?? helloName, config: config, isUsb: connection.isUsbTunnel,
            isTailscale: InterfaceFilter.isTailscale(connection.remoteEndpoint))
        report(.streaming(mode: acquired.mode, width: width, height: height, info: info))
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

    // MARK: Dọn dẹp

    private func teardown() async {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        await clipboard?.stop()
        clipboard = nil
        viewerReady = false
        await input?.shutdown()
        input = nil
        stopAudio()
        await pipeline?.stop()
        pipeline = nil
        await channel?.close()
        channel = nil
        await connection.close()
        await provider.release()
        await endWindowFit()
    }
}
