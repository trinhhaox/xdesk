import CoreMedia
import Foundation
import Network
import Observation
import os
import XdeskClipboard
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
    public private(set) var negotiatedCaps: Capabilities = []
    public var supportsHotReconfigure: Bool { negotiatedCaps.contains(.hotReconfigure) }
    public var supportsVideoPause: Bool { negotiatedCaps.contains(.videoPause) }
    /// Host cho phép chọn/kéo/đổi cỡ cửa sổ Mac (cần quyền `input` + Accessibility); UI ẩn "Chỉnh cửa sổ" khi `false`.
    public var supportsWindowControl: Bool { negotiatedCaps.contains(.windowControl) }
    /// `window.selected` gần nhất của host (kể cả `ok == false`, kèm `message`); nil khi chưa có/đã ngắt kết nối.
    public internal(set) var selectedWindow: WindowSelected?
    /// Gọi trên main actor mỗi khi host gửi `window.selected` (dùng khi cần phân biệt từng phản hồi, kể cả lỗi lặp lại).
    @ObservationIgnored public var onWindowSelected: (@MainActor (WindowSelected) -> Void)?
    public private(set) var lastFailureTransient = false
    /// Đích đã kết nối thành công (QR có thể thử nhiều địa chỉ); phiên mở lại dùng đích này.
    public internal(set) var connectedTarget: ViewerTarget?
    /// `ip:cổng` thực của host nhập tay vừa kết nối (tên MagicDNS đã phân giải); nil với host Bonjour.
    public internal(set) var connectedRemoteAddress: String?
    /// Chênh đồng hồ host − viewer (ms); dùng cho overlay đo độ trễ.
    public private(set) var clockOffsetMs: Double?
    /// Host đã ghép vừa từ chối IK ở lần `connect` gần nhất (id = fingerprint); UI đề nghị ghép đôi lại.
    public internal(set) var refusedHostId: String?
    /// Fingerprint host của phiên hiện tại (đặt sau khi bắt tay mã hoá thành công).
    @ObservationIgnored var connectedHostId: String?
    /// Khoá tĩnh Noise và tên của host đang kết nối (gắn vào dữ liệu ký mở khoá, hiện trong lời nhắc Face ID).
    @ObservationIgnored var connectedHostKey: [UInt8]?
    @ObservationIgnored var connectedHostName: String?
    @ObservationIgnored var unlockGate = UnlockRequestGate()
    /// Yêu cầu duyệt quyền điều khiển cho agent AI đang chờ trả lời (xem `agent.approve`); nil khi không có/đã hết hạn.
    public internal(set) var pendingAgentApproval: AgentApprovalRequest?
    public struct AgentHelpNotice: Sendable, Equatable, Identifiable {
        public var id: String { requestId }
        public let requestId: String
        public let reason: String
        public init(requestId: String, reason: String) {
            self.requestId = requestId
            self.reason = reason
        }
    }
    /// Yêu cầu người dùng hỗ trợ của Agent AI; nil khi không có/đã hoàn thành.
    public internal(set) var pendingAgentHelp: AgentHelpNotice?
    /// Host đã cấp quyền clipboard cho thiết bị này và phiên đang đồng bộ (iOS dùng để hiện nút "Gửi clipboard sang Mac").
    public internal(set) var clipboardAvailable = false
    /// Phiên đang phát âm thanh về viewer (bật nút tắt/bật tiếng cục bộ trong menu nổi).
    public internal(set) var audioAvailable = false
    /// Tắt tiếng cục bộ trên điện thoại (không tắt tiếng Mac).
    public internal(set) var audioMuted = false
    /// Danh sách màn hình vật lý của Mac (host gửi xuống khi kết nối để chọn khi có ≥ 2 màn hình).
    public internal(set) var hostDisplays: [DisplayInfo] = []
    /// Tiến trình truyền/nhận tệp hiện tại (nếu có).
    public internal(set) var activeFileTransfer: FileTransferProgress?
    /// Đường dẫn tệp vừa nhận xong từ Mac (Documents/Xdesk Downloads).
    public internal(set) var lastReceivedFileURL: URL?
    /// Thông báo lỗi truyền tệp gần nhất (nếu có).
    public internal(set) var lastFileTransferError: String?
    /// Kết quả đánh thức / mở khoá Mac gần nhất do host gửi về.
    public internal(set) var lastUnlockResult: SystemUnlockResult?
    /// Kết quả khoá màn hình Mac gần nhất do host gửi về.
    public internal(set) var lastLockResult: SystemLockResult?
    /// Trạng thái màn hình Mac do host báo (nil = host cũ/chưa báo). `videoAvailable == false`: Mac đang khoá/tắt màn hình, chưa có hình
    /// nhưng phiên vẫn sống: không coi thiếu khung hình là mất liên lạc và hiện nút mở khoá.
    public internal(set) var hostState: HostState?
    /// Mac đang khoá/tắt màn hình nên host chưa phát hình.
    public var hostVideoUnavailable: Bool { hostState?.videoAvailable == false }
    /// Số liệu phát audio (nil khi phiên không có audio); cập nhật mỗi 500 ms.
    public internal(set) var audioStats: AudioPlaybackStats?
    /// Ước lượng trễ audio đầu-cuối (ms): host giữ + rtt/2 + jitter buffer + thiết bị phát.
    public var audioLatencyEstimateMs: Int? { audioStats?.estimatedLatencyMs(rttMs: Int(rttMs ?? 0)) }
    public let renderer = VideoLayerRenderer()

    @ObservationIgnored let log = Logger(subsystem: "vn.xox.xdesk", category: "viewer-session")
    @ObservationIgnored let security: TransportSecurity
    @ObservationIgnored let deviceName: String
    @ObservationIgnored let trust: ViewerTrust?
    @ObservationIgnored let clipboardConfig: ClipboardConfig?
    @ObservationIgnored let audioConfig: AudioConfig?
    @ObservationIgnored let unlockSigner: (any UnlockSigner)?
    @ObservationIgnored var audioPlayer: AudioPlayer?
    @ObservationIgnored var clipboardSync: ClipboardSync?
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
    @ObservationIgnored var reconfigureWaiter: (id: UInt32, cont: CheckedContinuation<Bool, Never>)?
    @ObservationIgnored var earlyReadyIds: Set<UInt32> = []
    @ObservationIgnored var activeSendingFileId: String?
    @ObservationIgnored let fileCancelToken = FileCancelToken()
    @ObservationIgnored lazy var fileReceiver: FileTransferReceiver = FileTransferReceiver(
        directory: {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return docs.appendingPathComponent("Xdesk Downloads", isDirectory: true)
        },
        onProgress: { [weak self] progress in
            Task { @MainActor [weak self] in self?.activeFileTransfer = progress }
        },
        onCompleted: { [weak self] completion in
            Task { @MainActor [weak self] in self?.lastReceivedFileURL = completion.url }
        },
        onFailed: { [weak self] name, message in
            Task { @MainActor [weak self] in self?.lastFileTransferError = "\(name): \(message)" }
        }
    )
    #if DEBUG
    @ObservationIgnored var windowCount = 0
    #endif

    /// `trust` bắt buộc khi `security == .encrypted` (danh tính + host đã biết); plaintext (Debug) bỏ qua.
    public init(
        security: TransportSecurity, deviceName: String, trust: ViewerTrust? = nil, clipboard: ClipboardConfig? = nil,
        audio: AudioConfig? = nil, unlockSigner: (any UnlockSigner)? = nil
    ) {
        self.unlockSigner = unlockSigner
        self.clipboardConfig = clipboard
        self.audioConfig = audio
        self.security = security
        self.deviceName = deviceName
        self.trust = trust
    }

    /// Giờ host ước lượng cho thời điểm hiện tại của viewer (nil khi chưa đồng bộ).
    public func hostNowMs() -> Int64? { clock.viewerToHostMs(ClockSync.wallClockMs()) }

    public func connect(to target: ViewerTarget, config: DisplayConfig, auth: ViewerAuth = .automatic) async {
        await connect(candidates: [target], config: config, auth: auth)
    }

    public func connect(candidates: [ViewerTarget], config: DisplayConfig) async {
        await connect(candidates: candidates, config: config, auth: .automatic)
    }

    func connect(candidates: [ViewerTarget], config: DisplayConfig, auth: ViewerAuth) async {
        guard state == .idle || isFailed else { return }
        state = .connecting
        lastFailureTransient = false
        refusedHostId = nil
        connectedHostId = nil
        connectedHostKey = nil
        connectedHostName = nil
        unlockGate.reset()
        connectedRemoteAddress = nil
        do {
            try await establish(candidates, config: config, auth: auth)
            state = .streaming
        } catch {
            log.error("connect failed: \(error.localizedDescription, privacy: .public)")
            lastFailureTransient = Self.isTransientError(error)
            await teardown()
            state = .failed(error.localizedDescription)
        }
    }

    public func disconnect() async {
        if let connection { _ = try? await connection.send(.bye(Bye(reason: "viewer closed"))) }
        await teardown()
        state = .idle
    }

    var isFailed: Bool { if case .failed = state { true } else { false } }

    // MARK: Kết nối

    private func establish(_ candidates: [ViewerTarget], config: DisplayConfig, auth: ViewerAuth) async throws {
        let (conn, target) = try await openConnection(candidates)
        connectedTarget = target
        connection = conn
        try await authenticate(conn, target: target, auth: auth)
        try await finishEstablishing(conn, config: config, target: target)
    }

    /// Sau khi kênh đã xác thực: hello/welcome → kênh media (UDP, hoặc MediaOverTcp qua USB) → các vòng lặp của phiên.
    func finishEstablishing(_ conn: ControlConnection, config: DisplayConfig, target: ViewerTarget?) async throws {
        let result = try await conn.performViewerHandshake(name: deviceName, caps: offeredCaps(tunnel: conn.isUsbTunnel), display: config)
        negotiatedCaps = result.caps
        await startClipboard(on: conn, negotiated: result.caps)
        await registerUnlockKey(on: conn, negotiated: result.caps)
        startAudio(negotiated: result.caps)
        factory = SampleBufferFactory(codec: config.codec)
        streamId = result.ready.streamId
        let channel = try await openMediaChannel(conn, result: result, target: target)
        self.channel = channel
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

    private func openMediaChannel(_ conn: ControlConnection, result: ViewerHandshakeResult, target: ViewerTarget?) async throws -> UdpMediaChannel {
        if conn.isUsbTunnel {
            guard result.caps.contains(.mediaOverTcp) else { throw TransportError.protocolViolation("host không bật MediaOverTcp cho đường hầm USB") }
            return await UdpMediaChannel.overTcp(streamId: streamId, isViewer: true) { try await conn.sendMediaOverTcp($0) }
        }
        guard let host = await conn.resolvedRemoteHost else { throw TransportError.connectionFailed("không xác định được địa chỉ host") }
        if case .manual(_, let port)? = target { connectedRemoteAddress = "\(PeerAddressPolicy.normalized(host)):\(port)" }
        let channel = try await UdpMediaChannel.connect(streamId: streamId, host: host, port: result.ready.udpPort, keys: await conn.udpKeys)
        await wireResync(channel: channel, connection: conn)
        return channel
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
    func fail(_ message: String, transient: Bool = false) async {
        guard state == .streaming else { return }
        lastFailureTransient = transient
        setState(.failed(message))
        await teardown()
    }

    func teardown() async {
        if let waiter = reconfigureWaiter {
            reconfigureWaiter = nil
            waiter.cont.resume(returning: false)
        }
        earlyReadyIds.removeAll()
        hostDisplays = []
        hostState = nil
        activeFileTransfer = nil
        if let sendingId = activeSendingFileId {
            fileCancelToken.cancel(sendingId)
            activeSendingFileId = nil
        }
        await fileReceiver.cancelAll()
        negotiatedCaps = []
        pendingAgentApproval = nil
        pendingAgentHelp = nil
        selectedWindow = nil
        await stopClipboard()
        stopAudio()
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

    public func resolveAgentHelp() async {
        guard let help = pendingAgentHelp else { return }
        pendingAgentHelp = nil
        guard let connection else { return }
        do {
            _ = try await connection.send(.agentHelp(.resolve(requestId: help.requestId)))
        } catch {
            log.error("gửi agent.help resolve lỗi: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func setVideoPaused(_ paused: Bool) async {
        guard state == .streaming, supportsVideoPause, let connection else { return }
        let msg: ControlMessage = paused ? .videoPause(VideoPause(streamId: streamId)) : .videoResume(VideoResume(streamId: streamId))
        _ = try? await connection.send(msg)
    }

    /// Đổi cấu hình màn hình nóng ngay trong phiên đang mở (trả `false` nếu host cũ hoặc lỗi để tầng UI fallback reconnect).
    public func reconfigureDisplay(_ config: DisplayConfig) async -> Bool {
        guard state == .streaming, supportsHotReconfigure, let connection else { return false }
        guard reconfigureWaiter == nil else { return false }
        do {
            let reqId = try await connection.send(.displayReconfigure(config))
            let ok: Bool
            if earlyReadyIds.remove(reqId) != nil {
                ok = true
            } else {
                ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                    reconfigureWaiter = (reqId, cont)
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(5))
                        self?.finishReconfigure(id: reqId, ok: false)
                    }
                }
            }
            guard ok, state == .streaming else { return false }
            factory = SampleBufferFactory(codec: config.codec)
            renderer.flush()
            return true
        } catch {
            return false
        }
    }

    func finishReconfigure(id: UInt32, ok: Bool) {
        if let waiter = reconfigureWaiter, waiter.id == id {
            reconfigureWaiter = nil
            waiter.cont.resume(returning: ok)
        } else if ok {
            earlyReadyIds.insert(id)
        }
    }

    static func isTransientError(_ error: any Error) -> Bool {
        guard let te = error as? TransportError else { return false }
        switch te {
        case .connectionFailed, .connectionClosed, .timedOut, .noPeer:
            return true
        default:
            return false
        }
    }

    public func sendSystemLock() async {
        guard let connection else { return }
        _ = try? await connection.send(.systemLock(SystemLock()))
    }

    public func sendSystemUnlock() async { await requestUnlock() }

    public func clearLastUnlockResult() { lastUnlockResult = nil }
    public func clearLastLockResult() { lastLockResult = nil }
    public func existingUnlockPublicKey() async -> [UInt8]? { await unlockSigner?.existingPublicKey() }
    public func clearLastReceivedFile() { lastReceivedFileURL = nil }
    public func clearLastFileTransferError() { lastFileTransferError = nil }

    public func sendMediaKey(_ key: MediaKeyKind) async {
        guard state == .streaming, let connection else { return }
        _ = try? await connection.send(.mediaKey(MediaKey(key: key)))
    }

    public func cancelFileTransfer() async {
        if let sendingId = activeSendingFileId {
            fileCancelToken.cancel(sendingId)
            return
        }
        if let active = activeFileTransfer, active.direction == .receiving {
            await fileReceiver.handleCancel(FileCancel(id: active.id, reason: "cancelled"))
            _ = try? await connection?.send(.fileCancel(FileCancel(id: active.id, reason: "cancelled")))
        }
    }

    /// Host chỉ bật `.fileTransfer` khi thiết bị được cấp quyền gửi/nhận tệp; thiếu cap thì không gửi gì (UI nên ẩn nút).
    public var supportsFileTransfer: Bool { negotiatedCaps.contains(.fileTransfer) }

    public func sendFile(url: URL) async throws {
        guard let connection else { return }
        guard supportsFileTransfer else { throw ViewerFileTransferError.notPermitted }
        let transferId = UUID().uuidString
        activeSendingFileId = transferId
        defer {
            activeSendingFileId = nil
            fileCancelToken.clear(transferId)
        }
        try await FileTransferSender.sendFile(
            id: transferId,
            url: url,
            connection: connection,
            isCancelled: { [fileCancelToken] in fileCancelToken.isCancelled(transferId) },
            onProgress: { [weak self] progress in
                Task { @MainActor [weak self] in self?.activeFileTransfer = progress }
            }
        )
    }
}

public enum ViewerFileTransferError: Error, LocalizedError {
    case notPermitted
    public var errorDescription: String? { FileTransferDenial.message }
}

final class FileCancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelledIds: Set<String> = []
    func cancel(_ id: String) { lock.withLock { _ = cancelledIds.insert(id) } }
    func isCancelled(_ id: String) -> Bool { lock.withLock { cancelledIds.contains(id) } }
    func clear(_ id: String) { lock.withLock { _ = cancelledIds.remove(id) } }
}
