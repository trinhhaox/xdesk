import Foundation
import Observation
import XdeskClipboard
import XdeskCrypto
import XdeskTransport
import XdeskViewer
import XdeskWire

/// Danh sách host Bonjour + vòng đời kết nối viewer (một cửa sổ video tại một thời điểm).
@MainActor
@Observable
final class ViewerController {
    struct Options {
        var retina = false
        var fullScreen = false
        var latencyOverlay = false
    }

    private(set) var hosts: [DiscoveredHost] = []
    private(set) var session: ViewerSession?
    private(set) var errorMessage: String?
    /// Trạng thái ghép đôi của từng host Bonjour (theo `DiscoveredHost.id`); rỗng khi chạy không mã hoá.
    private(set) var hostStates: [String: ViewerTrust.HostState] = [:]
    /// Mã 6 số đang hiển thị để so với màn hình host, kèm câu trả lời của người dùng (nil = không đang so mã).
    private(set) var sasPrompt: SasPrompt?
    var options = Options()
    /// Máy nhập tay (Tailscale/MagicDNS/IP): Bonjour không đi qua Tailscale nên lưu lại để chọn lần sau.
    internal(set) var manualHosts: [ManualHost] = []
    internal(set) var manualHostError: String?
    /// Clipboard viewer đồng bộ với host; Debug có thể thay bằng pasteboard riêng (xem AutomationHooks).
    var clipboardPasteboard: any PasteboardAccess = SystemPasteboard()

    @ObservationIgnored private let security: SecurityCenter
    @ObservationIgnored private var browseTask: Task<Void, Never>?
    @ObservationIgnored private var window: ViewerWindow?
    @ObservationIgnored let manualStore: ManualHostStore?
    @ObservationIgnored let manualStoreError: String?

    init(security: SecurityCenter) {
        self.security = security
        do {
            manualStore = try ManualHostStore.openDefault()
            manualStoreError = nil
        } catch {
            manualStore = nil
            manualStoreError = error.localizedDescription
        }
    }

    var requiresPairing: Bool { AppSecurity.current == .encrypted }
    var isConnecting: Bool { session?.state == .connecting }

    func startBrowsing() {
        guard browseTask == nil else { return }
        browseTask = Task { [weak self] in
            for await list in BonjourBrowser().hosts() {
                self?.hosts = list
                await self?.refreshTrust()
            }
        }
    }

    func stopBrowsing() {
        browseTask?.cancel()
        browseTask = nil
    }

    func refreshTrust() async {
        guard let trust = security.viewerTrust, AppSecurity.current == .encrypted else {
            hostStates = [:]
            return
        }
        var next: [String: ViewerTrust.HostState] = [:]
        for host in hosts { next[host.id] = await trust.state(of: host) }
        hostStates = next
    }

    /// Ghép đôi bằng mã 6 số: hiện `sasPrompt`; xong khi cả máy này lẫn host bấm "Khớp" (hoặc lỗi/quá hạn).
    func pairWithCode(to target: ViewerTarget, title: String) async {
        sasPrompt = nil
        await connect(to: target, title: title, auth: .sas(onCode: { [weak self] prompt in
            await MainActor.run { if prompt.isPending { self?.sasPrompt = prompt } }
        }))
        sasPrompt = nil
    }

    /// Bỏ khoá cũ của host đã đổi khoá; lần kết nối sau sẽ phải ghép đôi lại.
    func forgetKnownHost(id: String) async {
        await security.forgetHost(deviceId: id)
        await refreshTrust()
    }

    /// `auth`: `.automatic` = host đã ghép → IK; `.sas` = so mã 6 số (UI nhận mã qua `onCode`).
    func connect(to target: ViewerTarget, title: String, auth: ViewerAuth = .automatic) async {
        await run(title: title) { await $0.connect(to: target, config: $1, auth: auth) }
    }

    /// Ghép đôi bằng URI QR (`xdesk://pair?...`), thử lần lượt các địa chỉ trong QR.
    func pair(with uri: PairingURI, title: String) async {
        await run(title: title) { await $0.pair(with: uri, config: $1) }
    }

    /// Đường hầm USB (iPhone/iPad là TCP-server): Mac-viewer chỉ dùng để kiểm thử loopback.
    func connectTunnel(_ tunnel: ControlConnection, title: String) async {
        await run(title: title) { await $0.connect(tunnel: tunnel, config: $1) }
    }

    private func run(title: String, _ start: (ViewerSession, DisplayConfig) async -> Void) async {
        guard session == nil else { return }
        errorMessage = nil
        let session = ViewerSession(
            security: AppSecurity.current, deviceName: HostIdentity.displayName, trust: security.viewerTrust,
            clipboard: ClipboardConfig(pasteboard: clipboardPasteboard, autoWatch: true), audio: AudioConfig())
        self.session = session
        await start(session, displayConfig())
        await security.refresh()
        await refreshTrust()
        await recordManualConnection(session)
        guard case .streaming = session.state else {
            if case .failed(let message) = session.state { errorMessage = message }
            self.session = nil
            return
        }
        window = ViewerWindow(
            session: session, title: title, fullScreen: options.fullScreen, latencyOverlay: options.latencyOverlay,
            onClose: { [weak self] in Task { await self?.disconnect() } }
        )
    }

    func disconnect() async {
        let current = session
        session = nil
        window?.close()
        window = nil
        await current?.disconnect()
    }

    private func displayConfig() -> DisplayConfig {
        options.retina
            ? DisplayConfig(w: 3840, h: 2400, scale: 2, fps: 60, codec: .h264)
            : DisplayConfig(w: 1920, h: 1200, scale: 1, fps: 60, codec: .h264)
    }
}
