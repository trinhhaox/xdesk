import Observation
import UIKit
import XdeskClipboard
import XdeskCrypto
import XdeskTransport
import XdeskViewer
import XdeskWire

/// Trạng thái cả app: danh sách host (Bonjour), phiên xem, vòng đời nền/foreground và đổi cấu hình khi xoay máy.
@MainActor
@Observable
final class StreamViewModel {
    private(set) var hosts: [DiscoveredHost] = []
    private(set) var localNetworkDenied = false
    var errorMessage: String?
    /// `true` từ lúc bấm kết nối tới khi người dùng thoát hoặc kết nối hỏng → màn hình stream thay danh sách host.
    var inStream = false
    /// Bản sao (mặc định, hay dùng để điều khiển Mac) hay mở rộng màn hình Mac; nhớ giữa các lần mở app.
    var screenMode: ScreenMode = ScreenMode(rawValue: UserDefaults.standard.string(forKey: "xdesk.screenMode") ?? "") ?? .mirror {
        didSet {
            UserDefaults.standard.set(screenMode.rawValue, forKey: "xdesk.screenMode")
            displayOptionsChanged()
        }
    }
    /// Kiểu vừa khung của Bản sao (Giống màn hình Mac / Vừa với điện thoại / Tối ưu thao tác); nhớ giữa các lần mở app.
    var mirrorFit: MirrorFit = MirrorFit(rawValue: UserDefaults.standard.string(forKey: "xdesk.mirrorFit") ?? "") ?? .fitDevice {
        didSet {
            UserDefaults.standard.set(mirrorFit.rawValue, forKey: "xdesk.mirrorFit")
            displayOptionsChanged()
        }
    }
    let session: ViewerSession
    /// Danh tính + host đã ghép của iPhone/iPad; nil khi không mở được Keychain/file (xem `securityError`).
    let security: DeviceSecurityStores?
    let securityError: String?
    let trust: ViewerTrust?
    /// Trạng thái ghép đôi của từng host Bonjour (theo `DiscoveredHost.id`); rỗng khi chạy không mã hoá.
    var hostStates: [String: ViewerTrust.HostState] = [:]
    /// Các host đã ghép (cho màn Cài đặt bảo mật).
    var knownHosts: [PairedDevice] = []
    /// Mã 6 số đang hiển thị để so với màn hình Mac (nil = không đang so mã).
    var sasCode: String?
    /// Đang ghép đôi (QR hoặc mã 6 số): màn hình stream hiện "Đang chờ Mac xác nhận…".
    var isPairing = false
    /// Mac đã ghép vừa từ chối kết nối (thường do đã thu hồi): danh sách hỏi có ghép đôi lại không.
    var refusedHost: RefusedHost?
    var manualHosts: [ManualHost] = []
    var manualHostError: String?
    /// Kết quả lần bấm "Gửi clipboard sang Mac" gần nhất (toast).
    var clipboardNotice: String?
    @ObservationIgnored let manualStore: Result<ManualHostStore, any Error>

    struct RefusedHost: Identifiable {
        let target: ViewerTarget
        let hostId: String
        var id: String { hostId }
    }

    @ObservationIgnored private var browseTask: Task<Void, Never>?
    @ObservationIgnored var usbListener: UsbListener?
    /// Đích của lần kết nối gần nhất; giữ sau khi lỗi để "Thử lại" / "Ghép đôi" trên thẻ lỗi.
    @ObservationIgnored private(set) var target: ViewerTarget?
    /// Tên hiển thị của đích gần nhất ("Đang kết nối tới …", thẻ lỗi).
    private(set) var connectingName: String?
    /// Cấu hình màn hình đang dùng; cho lớp nhập liệu biết kích thước màn hình host theo điểm.
    var currentConfig: DisplayConfig?
    @ObservationIgnored private var isRestarting = false
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private lazy var orientation = OrientationObserver { [weak self] _ in self?.screenSettled() }

    init() {
        manualStore = Result { try ManualHostStore.openDefault() }
        // iOS chỉ đọc UIPasteboard khi người dùng bấm nút (tránh banner "đã dán từ"), không tự theo dõi.
        let clipboard = ClipboardConfig(pasteboard: SystemPasteboard(), autoWatch: false)
        let audio = AudioConfig()
        do {
            let stores = try DeviceSecurityStores.openDefault()
            let trust = ViewerTrust(identity: stores.identity, knownHosts: stores.knownHosts)
            security = stores
            securityError = nil
            self.trust = trust
            session = ViewerSession(security: AppSecurity.current, deviceName: UIDevice.current.name, trust: trust, clipboard: clipboard, audio: audio)
        } catch {
            security = nil
            trust = nil
            securityError = error.localizedDescription
            session = ViewerSession(security: AppSecurity.current, deviceName: UIDevice.current.name, clipboard: clipboard, audio: audio)
        }
    }

    // MARK: Bonjour

    func startBrowsing() {
        guard browseTask == nil else { return }
        browseTask = Task { [weak self] in
            for await update in BonjourBrowser().updates() {
                switch update {
                case .hosts(let list):
                    self?.hosts = list
                    self?.localNetworkDenied = false
                    await self?.refreshTrust()
                case .localNetworkDenied: self?.localNetworkDenied = true
                }
            }
        }
    }

    func stopBrowsing() {
        browseTask?.cancel()
        browseTask = nil
    }

    // MARK: Kết nối

    /// Kết nối tới host đã ghép (IK). Host chưa ghép → `pairingRequired`.
    func connect(to target: ViewerTarget) async {
        await begin(target) { await self.session.connect(to: target, config: $0) }
    }

    func begin(_ target: ViewerTarget, _ first: (DisplayConfig) async -> Void) async {
        guard !inStream, let metrics = ScreenMetrics.current(), let config = plan(metrics) else {
            if !inStream { errorMessage = "Không đọc được kích thước màn hình." }
            return
        }
        self.target = target
        connectingName = displayName(of: target)
        errorMessage = nil
        inStream = true
        currentConfig = config
        await first(config)
        // Người dùng bấm Huỷ khi đang kết nối: nếu phiên vẫn kịp thành công thì đóng lại, không để stream chạy ngầm.
        guard inStream else {
            if session.state != .idle { await session.disconnect() }
            return
        }
        await refreshTrust()
        await recordManualConnection()
        self.target = session.connectedTarget ?? target
        if let hostId = session.refusedHostId { refusedHost = RefusedHost(target: target, hostId: hostId) }
        failIfNeeded()
    }

    /// Thoát về danh sách host, gửi `bye` lịch sự (cũng là nút Huỷ khi đang kết nối).
    func disconnect() async {
        inStream = false
        suspended = false
        await session.disconnect()
    }

    private func start(_ target: ViewerTarget, _ config: DisplayConfig) async {
        currentConfig = config
        await session.connect(to: target, config: config)
        failIfNeeded()
    }

    /// Phiên hỏng (host đóng, mạng mất) → về danh sách, giữ thông báo lỗi. An toàn khi gọi lặp.
    func failIfNeeded() {
        guard inStream, case .failed(let message) = session.state else { return }
        inStream = false
        errorMessage = message
        // Phiên có thể vừa bị thu hồi (host đã bị xoá khỏi danh sách) → cập nhật nhãn "Đã ghép"/"Chưa ghép".
        Task {
            await session.disconnect()
            await refreshTrust()
        }
    }

    // MARK: Vòng đời scene

    /// iOS treo socket khi vào nền → báo `bye` để host giữ màn hình ảo rồi dừng stream.
    func enterBackground() async {
        guard inStream, session.state == .streaming || session.state == .connecting else { return }
        suspended = true
        await session.disconnect()
    }

    func enterForeground() async {
        guard suspended, inStream, let target else { return }
        suspended = false
        guard let config = plan(orientation.latest ?? ScreenMetrics.current()) else { return }
        await start(target, config)
    }

    // MARK: Xoay màn hình

    func screenChanged(_ metrics: ScreenMetrics) { orientation.update(metrics) }

    private func screenSettled() {
        guard inStream, !suspended, !isRestarting, session.state == .streaming else { return }
        Task { await syncDisplayConfig() }
    }

    /// Đổi Bản sao/Mở rộng hoặc kiểu vừa khung giữa phiên → mở lại phiên với `display.config` mới (như khi xoay máy).
    private func displayOptionsChanged() {
        guard inStream, !suspended, !isRestarting, session.state == .streaming else { return }
        Task { await syncDisplayConfig() }
    }

    /// Host chưa đổi mode giữa phiên → đổi cấu hình bằng cách mở lại phiên với `display.config` mới.
    private func syncDisplayConfig() async {
        isRestarting = true
        defer { isRestarting = false }
        while inStream, !suspended, let target, let config = plan(orientation.latest ?? ScreenMetrics.current()), config != currentConfig {
            await session.disconnect()
            await start(target, config)
            guard session.state == .streaming else { return }
        }
    }

    func plan(_ metrics: ScreenMetrics?) -> DisplayConfig? {
        guard let metrics else { return nil }
        return DisplayConfigPlanner.config(
            pointsWidth: metrics.size.width, pointsHeight: metrics.size.height, scale: metrics.scale,
            mode: screenMode, mirrorFit: mirrorFit
        )
    }
}

/// Luôn `.encrypted`; plaintext chỉ tồn tại ở build Debug và chỉ khi truyền `--plaintext`.
enum AppSecurity {
    static var current: TransportSecurity {
        #if DEBUG
        CommandLine.arguments.contains("--plaintext") ? .devPlaintext : .encrypted
        #else
        .encrypted
        #endif
    }
}
