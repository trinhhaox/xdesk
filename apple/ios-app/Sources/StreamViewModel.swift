import Observation
import UIKit
import XdeskTransport
import XdeskViewer
import XdeskWire

/// Trạng thái cả app: danh sách host (Bonjour), phiên xem, vòng đời nền/foreground và đổi cấu hình khi xoay máy.
@MainActor
@Observable
final class StreamViewModel {
    private(set) var hosts: [DiscoveredHost] = []
    private(set) var localNetworkDenied = false
    private(set) var errorMessage: String?
    /// `true` từ lúc bấm kết nối tới khi người dùng thoát hoặc kết nối hỏng → màn hình stream thay danh sách host.
    private(set) var inStream = false
    /// Mở rộng hay bản sao màn hình Mac; nhớ giữa các lần mở app.
    var screenMode: ScreenMode = ScreenMode(rawValue: UserDefaults.standard.string(forKey: "xdesk.screenMode") ?? "") ?? .extend {
        didSet { UserDefaults.standard.set(screenMode.rawValue, forKey: "xdesk.screenMode") }
    }
    let session = ViewerSession(security: AppSecurity.current, deviceName: UIDevice.current.name)

    @ObservationIgnored private var browseTask: Task<Void, Never>?
    @ObservationIgnored private var target: ViewerTarget?
    @ObservationIgnored private var currentConfig: DisplayConfig?
    @ObservationIgnored private var isRestarting = false
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private lazy var orientation = OrientationObserver { [weak self] _ in self?.screenSettled() }

    // MARK: Bonjour

    func startBrowsing() {
        guard browseTask == nil else { return }
        browseTask = Task { [weak self] in
            for await update in BonjourBrowser().updates() {
                switch update {
                case .hosts(let list): self?.hosts = list; self?.localNetworkDenied = false
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

    func connect(to target: ViewerTarget) async {
        guard !inStream, let metrics = ScreenMetrics.current(), let config = plan(metrics) else {
            if !inStream { errorMessage = "Không đọc được kích thước màn hình." }
            return
        }
        self.target = target
        errorMessage = nil
        inStream = true
        await start(target, config)
    }

    /// Thoát về danh sách host, gửi `bye` lịch sự.
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
        Task { await session.disconnect() }
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

    /// Host chưa đổi mode giữa phiên → đổi cấu hình bằng cách mở lại phiên với `display.config` mới.
    private func syncDisplayConfig() async {
        isRestarting = true
        defer { isRestarting = false }
        while inStream, !suspended, let target, let config = plan(orientation.latest), config != currentConfig {
            await session.disconnect()
            await start(target, config)
            guard session.state == .streaming else { return }
        }
    }

    private func plan(_ metrics: ScreenMetrics?) -> DisplayConfig? {
        guard let metrics else { return nil }
        return DisplayConfigPlanner.config(
            pointsWidth: metrics.size.width, pointsHeight: metrics.size.height, scale: metrics.scale, mode: screenMode
        )
    }
}

enum AppSecurity {
    static var current: TransportSecurity {
        #if DEBUG
        .devPlaintext
        #else
        .encrypted
        #endif
    }
}
