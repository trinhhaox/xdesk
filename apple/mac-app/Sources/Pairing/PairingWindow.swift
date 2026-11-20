import AppKit
import Observation
import SwiftUI
import XdeskCrypto
import XdeskTransport

/// Điều phối cửa sổ ghép đôi trên Mac: cửa sổ QR (menu "Ghép đôi thiết bị mới…") và hộp thoại cho phép khi có yêu cầu.
/// Cả hai là `SecureWindow` (không chụp được, loại khỏi stream).
@MainActor
@Observable
final class PairingCoordinator {
    let security: SecurityCenter
    private let host: HostController
    private(set) var qrIssuedAt: Date?
    private(set) var justPaired = false

    @ObservationIgnored private var qrWindow: SecureWindow?
    @ObservationIgnored private var approvalWindow: SecureWindow?
    @ObservationIgnored private var devicesWindow: NSWindow?
    @ObservationIgnored private var lastQr: PairingURI?
    @ObservationIgnored private var wasReady = false

    init(security: SecurityCenter, host: HostController) {
        self.security = security
        self.host = host
        observe()
    }

    var availability: PairingAvailability {
        var port: UInt16?
        if case .listening(let listening) = host.status { port = listening }
        return .evaluate(encrypted: AppSecurity.current == .encrypted, port: port, activeViewers: host.activeViewerCount)
    }

    #if DEBUG
    var qrWindowForTesting: SecureWindow? { qrWindow }
    var approvalWindowForTesting: SecureWindow? { approvalWindow }
    #endif

    func showDevicesWindow() {
        if devicesWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = String(localized: "Xdesk — Thiết bị đã ghép")
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: PairedDevicesSettings(security: security))
            window.center()
            devicesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        devicesWindow?.makeKeyAndOrderFront(nil)
    }

    func showQrWindow() async {
        if qrWindow == nil {
            qrWindow = SecureWindow(
                title: String(localized: "Xdesk — Ghép đôi thiết bị mới"), floating: false,
                onClose: { [weak self] in self?.qrWindowClosed() }, content: PairingQrView(coordinator: self))
        }
        qrWindow?.show()
        wasReady = availability.blockedMessage == nil
        await refreshQr()
    }

    /// Phát mã mới nếu đủ điều kiện; ngược lại giữ cửa sổ ở trạng thái giải thích.
    func refreshQr() async {
        justPaired = false
        guard case .ready(let port) = availability else { return }
        await security.startQrPairing(port: port)
    }

    private func qrWindowClosed() {
        qrWindow = nil
        qrIssuedAt = nil
        Task { await security.stopQrPairing() }
    }

    // MARK: Đồng bộ trạng thái

    /// Đăng ký lại sau mỗi lần có thay đổi (Observation chỉ bắn một lần).
    private func observe() {
        withObservationTracking {
            _ = security.pendingPairing
            _ = security.qrURI
            _ = availability
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sync()
                self?.observe()
            }
        }
    }

    private func sync() {
        syncApproval()
        guard qrWindow != nil else { return }
        let ready: Bool
        if case .ready = availability { ready = true } else { ready = false }
        if !ready, security.qrURI != nil { Task { await security.stopQrPairing() } }
        // Host vừa sẵn sàng (đang khởi động hoặc hết phiên xem) trong lúc cửa sổ mở → tự phát mã.
        if ready, !wasReady, security.qrURI == nil { Task { await refreshQr() } }
        wasReady = ready
        guard security.qrURI != lastQr else { return }
        if security.qrURI == nil, case .qrClosed(.paired)? = security.lastEvent { justPaired = true }
        lastQr = security.qrURI
        qrIssuedAt = security.qrURI == nil ? nil : Date()
    }

    private func syncApproval() {
        guard let request = security.pendingPairing else {
            approvalWindow?.close()
            return
        }
        guard approvalWindow == nil else { return }
        let window = SecureWindow(
            title: String(localized: "Xdesk — Ghép đôi"), floating: true,
            onClose: { [weak self] in
                self?.approvalWindow = nil
                // Đóng bằng nút X = từ chối; không đụng tới yêu cầu mới hơn nếu yêu cầu này đã được quyết.
                if self?.security.pendingPairing == request { self?.security.resolvePairing(.reject) }
            },
            content: SasConfirmView(request: request) { [weak self] decision in self?.security.resolvePairing(decision) })
        approvalWindow = window
        window.show()
    }
}
