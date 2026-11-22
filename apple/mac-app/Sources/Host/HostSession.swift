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
    let onAgentHelp: @Sendable (_ requestId: String, _ resolved: Bool) -> Void
    let log = Logger(subsystem: "vn.xox.xdesk", category: "host-session")
    private(set) var channel: UdpMediaChannel?
    var pipeline: HostPipeline?
    var audio: HostAudioStreamer?
    var mutedLocalOutput = false
    let audioSettings: HostAudioSettings
    var input: HostInputService?
    var windowControl: WindowControlService?
    var viewerReady = false
    /// Tên thiết bị viewer tự khai trong Hello (dự phòng khi chưa có peer đã xác thực).
    private var helloName = ""
    /// Quyền của thiết bị đã ghép (plaintext Debug: mặc định). `view` tắt → từ chối phiên; `input` tắt → bỏ input.
    private(set) var permissions = DevicePermissions.default {
        didSet { fileGate.set(permissions.fileTransfer) }
    }
    var bitrate = BitrateController(initialKbps: HostSession.initialBitrateKbps)
    private var tasks: [Task<Void, Never>] = []
    var framePumpTask: Task<Void, Never>?
    let frameCounter = FrameCounter()
    let pipelineOrigin = ProcessInfo.processInfo.systemUptime
    /// Đọc trạng thái khoá/ngủ của Mac và tín hiệu "capture được lại" (tiêm được để test).
    let screenState: @Sendable () -> LockScreenState
    let screenWakeEvents: @Sendable () -> AsyncStream<Void>
    let videoRetryPoll: Duration
    var videoConfig: DisplayConfig?
    var videoShape: VideoShape?
    /// Mac đang khoá/tắt màn hình nên chưa capture được; phiên vẫn sống (xem `HostSession+Video`).
    var videoUnavailable = false
    var videoGeneration = 0
    var videoRetryTask: Task<Void, Never>?
    var lastHostState: HostState?
    var videoBusy = false
    var videoWaiters: [CheckedContinuation<Void, Never>] = []
    var ended = false
    private var activeUdpPort: UInt16 = 1
    private var isMediaOverTcp = false
    var videoPaused = false
    let pasteboard: (any PasteboardAccess)?
    let permissionLookup: @Sendable ([UInt8]) async -> DevicePermissions?
    let extendSideLookup: @Sendable () async -> ExtendSide
    let remoteUnlockLookup: @Sendable () async -> Bool
    let onTransferProgress: @Sendable (FileTransferProgress?) -> Void
    let onFileReceived: @Sendable (FileTransferCompletion) -> Void
    let onFileFailed: @Sendable (String, String) -> Void
    var remoteUnlockSettingSnapshot: Bool
    let unlockLimits: UnlockRateLimits
    let hostStaticKey: @Sendable () async -> [UInt8]?
    var unlockMismatchNotified = false
    var unlockChallenges = UnlockChallengeBook(ttl: Double(UnlockAttestation.challengeTTLms) / 1000)
    let unlockKeyLookup: @Sendable ([UInt8]) async -> [UInt8]?
    let unlockKeyEnroll: @Sendable (_ viewerKey: [UInt8], _ unlockKey: [UInt8]) async -> PairedDevicesStore.UnlockKeyEnrollment
    private(set) var negotiatedCaps: Capabilities = []
    var clipboard: ClipboardSync?
    var activeSendingFileId: String?
    let fileCancelToken = HostFileCancelToken()
    let fileGate = HostFileGate()
    var lastDenyNoticeAt: ContinuousClock.Instant?
    var expectingFileBulk = false
    var filePermissionWatch: Task<Void, Never>?
    lazy var fileReceiver: FileTransferReceiver = FileTransferReceiver(
        directory: { Self.downloadsDirectory },
        onProgress: onTransferProgress,
        onCompleted: onFileReceived,
        onFailed: onFileFailed
    )

    init(
        connection: ControlConnection, provider: VirtualDisplayProvider, windowFit: WindowFitter? = nil, caps: Capabilities,
        report: @escaping @Sendable (HostSessionState) -> Void,
        onSecureInput: @escaping @Sendable (Bool) -> Void = { _ in },
        onAgentAnswer: @escaping @Sendable (String, Bool) -> Void = { _, _ in },
        onAgentHelp: @escaping @Sendable (String, Bool) -> Void = { _, _ in },
        pasteboard: (any PasteboardAccess)? = nil,
        audioSettings: HostAudioSettings = HostAudioSettings(),
        permissionLookup: @escaping @Sendable ([UInt8]) async -> DevicePermissions? = { _ in nil },
        extendSideLookup: @escaping @Sendable () async -> ExtendSide = { .right },
        remoteUnlockEnabled: Bool = false,
        remoteUnlockLookup: @escaping @Sendable () async -> Bool = { false },
        unlockLimits: UnlockRateLimits = UnlockRateLimits(),
        hostStaticKey: @escaping @Sendable () async -> [UInt8]? = { nil },
        unlockKeyLookup: @escaping @Sendable ([UInt8]) async -> [UInt8]? = { _ in nil },
        unlockKeyEnroll: @escaping @Sendable ([UInt8], [UInt8]) async -> PairedDevicesStore.UnlockKeyEnrollment = { _, _ in .notPermitted },
        onTransferProgress: @escaping @Sendable (FileTransferProgress?) -> Void = { _ in },
        onFileReceived: @escaping @Sendable (FileTransferCompletion) -> Void = { _ in },
        onFileFailed: @escaping @Sendable (String, String) -> Void = { _, _ in },
        screenState: @escaping @Sendable () -> LockScreenState = { LockScreenState.current() },
        screenWakeEvents: @escaping @Sendable () -> AsyncStream<Void> = { ScreenWakeSignals.stream() },
        videoRetryPoll: Duration = .seconds(3)
    ) {
        self.screenState = screenState
        self.screenWakeEvents = screenWakeEvents
        self.videoRetryPoll = videoRetryPoll
        self.audioSettings = audioSettings
        self.pasteboard = pasteboard
        self.permissionLookup = permissionLookup
        self.extendSideLookup = extendSideLookup
        self.remoteUnlockSettingSnapshot = remoteUnlockEnabled
        self.remoteUnlockLookup = remoteUnlockLookup
        self.unlockLimits = unlockLimits
        self.hostStaticKey = hostStaticKey
        self.unlockKeyLookup = unlockKeyLookup
        self.unlockKeyEnroll = unlockKeyEnroll
        self.onTransferProgress = onTransferProgress
        self.onFileReceived = onFileReceived
        self.onFileFailed = onFileFailed
        self.onAgentAnswer = onAgentAnswer
        self.onAgentHelp = onAgentHelp
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
            remoteUnlockSettingSnapshot = await remoteUnlockLookup()
            let result = try await connection.performHostHandshake(caps: negotiableCaps, sessionId: UUID().uuidString) { [self] hello, display in
                try await prepare(hello, display)
            }
            negotiatedCaps = result.caps
            if result.caps.contains(.clipboard) { await startClipboard() }
            if result.caps.contains(.fileTransfer) { startFilePermissionWatch() }
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

    /// Gửi thông báo agent cần trợ giúp tới viewer.
    func sendAgentHelp(_ help: AgentHelp) async {
        guard viewerReady else { return }
        do { _ = try await connection.send(.agentHelp(help)) } catch {
            log.error("gửi agent.help lỗi: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleSystemLock() async {
        guard await livePermissions().input else {
            _ = try? await connection.send(.systemLockResult(SystemLockResult(
                ok: false, message: "Thiết bị này chưa được cấp quyền điều khiển Mac")))
            return
        }
        log.notice("Nhận lệnh khóa màn hình Mac từ xa")
        let outcome = await RemoteLockExecutor.lockScreen()
        log.notice("Khoá màn hình từ xa: \(String(describing: outcome), privacy: .public)")
        let result = RemoteLockExecutor.result(for: outcome)
        _ = try? await connection.send(.systemLockResult(SystemLockResult(ok: result.ok, message: result.message)))
    }

    // MARK: Chuẩn bị (trong handshake)

    private func prepare(_ hello: Hello, _ display: DisplayConfig) async throws -> DisplayReady {
        helloName = hello.name
        permissions = await connection.peer?.permissions ?? .default
        guard permissions.view else { throw TransportError.rejected(reason: "permission", detail: "thiết bị này không có quyền xem") }
        let viewerOffersMediaOverTcp = Capabilities(rawValue: hello.caps).contains(.mediaOverTcp)
        if connection.isUsbTunnel || (connection.isLoopback && viewerOffersMediaOverTcp) {
            if connection.isUsbTunnel && !viewerOffersMediaOverTcp {
                throw TransportError.rejected(reason: "transport", detail: "đường hầm USB cần MediaOverTcp")
            }
            isMediaOverTcp = true
            channel = await UdpMediaChannel.overTcp(streamId: Self.streamId, isViewer: false) { [connection] in try await connection.sendMediaOverTcp($0) }
            activeUdpPort = 1
            // Không có UDP: udpPort chỉ là chỗ giữ chỗ (≠ 0 theo spec) và bị viewer bỏ qua khi đã thương lượng MediaOverTcp.
            return DisplayReady(udpPort: 1, streamId: Self.streamId)
        }
        isMediaOverTcp = false
        let channel = try await UdpMediaChannel.listen(
            streamId: Self.streamId, allowedPeerHost: connection.remoteHost, keys: await connection.udpKeys)
        self.channel = channel
        let port = await channel.localPort
        activeUdpPort = port
        await channel.setResyncSink { [connection] resync in
            do { _ = try await connection.send(.rekeyResync(resync)) } catch {
                // Kênh control đã đóng: phiên sắp kết thúc.
            }
        }
        return DisplayReady(udpPort: port, streamId: Self.streamId)
    }

    private func startPipeline(_ config: DisplayConfig, caps: Capabilities) async throws {
        guard let channel else { throw TransportError.noPeer }
        try await startVideoOrDefer(config)
        if input == nil { await startInput(displayID: CGMainDisplayID()) }
        tasks.append(Task {
            for await event in channel.events {
                switch event {
                case .peerConnected:
                    await handlePeerConnected()
                case .packet(let packet): await handleInputPacket(packet)
                case .linkLost: await connection.close()
                default: break
                }
            }
        })
        await reportCurrentStreaming(config)
        await sendDisplayListIfSupported()
    }

    private func handlePeerConnected() async {
        viewerReady = true
        audio?.setActive(true)
        if videoPaused || videoUnavailable {
            // Thông báo ngay cho viewer biết kênh UDP đã thông dù chưa phát khung hình nào.
            let probe = MediaPacket(header: MediaHeader(type: .probe, streamId: Self.streamId, frameNo: 0), payload: [])
            try? await channel?.sendPacket(probe)
        } else {
            pipeline?.beginStreaming()
        }
    }

    func setVideoPaused(_ paused: Bool) async {
        guard videoPaused != paused else { return }
        videoPaused = paused
        await pipeline?.setVideoPaused(paused)
        if !paused && viewerReady { pipeline?.beginStreaming() }
    }

    func reconfigureDisplay(_ config: DisplayConfig, requestId: UInt32) async throws {
        guard channel != nil else { return }
        log.notice("reconfigure \(config.w)x\(config.h) mode=\(config.screenMode.rawValue, privacy: .public) fit=\(config.fit.rawValue, privacy: .public)")
        try await startVideoOrDefer(config)
        _ = try await connection.send(.displayReady(DisplayReady(udpPort: activeUdpPort, streamId: Self.streamId)), id: requestId)
        await reportCurrentStreaming(config)
        await sendDisplayListIfSupported()
    }

    func reportStreaming(mode: DisplayMode, width: Int, height: Int, config: DisplayConfig) async {
        let peerName = await connection.peer?.name
        let info = ViewerSessionInfo.make(
            name: peerName ?? helloName, config: config, isUsb: connection.isUsbTunnel || isMediaOverTcp,
            isTailscale: InterfaceFilter.isTailscale(connection.remoteEndpoint))
        report(.streaming(mode: mode, width: width, height: height, info: info))
    }

    static func pumpFrames(_ encoder: VideoEncoder, counter: FrameCounter, to channel: UdpMediaChannel) async {
        do {
            for try await frame in encoder.frames {
                try await channel.sendFrame(frame.data, frameNo: counter.next(), ptsMs: frame.ptsMs, isKeyframe: frame.isKeyframe)
            }
        } catch {
            Logger(subsystem: "vn.xox.xdesk", category: "host-session").error("frame pump stopped: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Dọn dẹp

    private func teardown() async {
        videoRetryTask?.cancel()
        videoRetryTask = nil
        await withVideoLock { ended = true }
        isMediaOverTcp = false
        framePumpTask?.cancel()
        framePumpTask = nil
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        filePermissionWatch?.cancel()
        filePermissionWatch = nil
        await clipboard?.stop()
        clipboard = nil
        if let activeId = activeSendingFileId {
            fileCancelToken.cancel(activeId)
            activeSendingFileId = nil
        }
        await fileReceiver.cancelAll()
        onTransferProgress(nil)
        viewerReady = false
        await input?.shutdown()
        input = nil
        await shutdownWindowControl()
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

final class FrameCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt32 = 0

    func next() -> UInt32 {
        lock.withLock {
            let current = value
            value &+= 1
            return current
        }
    }
}

final class HostFileCancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelledIds: Set<String> = []
    func cancel(_ id: String) { lock.withLock { _ = cancelledIds.insert(id) } }
    func isCancelled(_ id: String) -> Bool { lock.withLock { cancelledIds.contains(id) } }
    func clear(_ id: String) { lock.withLock { _ = cancelledIds.remove(id) } }
}
