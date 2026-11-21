import Foundation
import Observation
import os
import XdeskClipboard
import XdeskCrypto
import XdeskTransport
import XdeskWire

/// Bật/tắt host: Bonjour + listener TCP; mỗi kết nối vào thành một `HostSession`.
@MainActor
@Observable
final class HostController {
    static let preferredPort: UInt16 = 47800

    enum Status: Equatable {
        case stopped
        case starting
        case listening(port: UInt16)
        case failed(String)
    }

    private(set) var status: Status = .stopped
    private(set) var sessionStates: [UUID: HostSessionState] = [:]
    /// Một app đang bật Secure Event Input nên chữ gõ từ xa có thể không vào được ô đích.
    private(set) var secureInputActive = false

    /// Clipboard dùng cho đồng bộ; Debug có thể thay bằng pasteboard riêng (xem AutomationHooks) để không đụng clipboard thật.
    var clipboardPasteboard: any PasteboardAccess = SystemPasteboard()
    /// "Cho phép kết nối qua Tailscale": mặc định tắt; áp dụng ngay cho kết nối mới.
    private(set) var allowTailscale = UserDefaults.standard.bool(forKey: HostController.allowTailscaleKey)
    private static let allowTailscaleKey = "xdesk.host.allowTailscale"

    let audioOptions = HostAudioOptions()
    let windowFit = WindowFitter()
    /// "Tự co giãn cửa sổ ứng dụng cho vừa màn hình" (Bản sao fitDevice/touch): mặc định bật.
    private(set) var fitWindows = WindowFitter.isEnabledByUser
    let usb = UsbDeviceMonitor()
    var usbMessage: String?
    private let log = Logger(subsystem: "vn.xox.xdesk", category: "host-controller")
    let security: SecurityCenter
    private var listener: ControlListener?
    /// AgentController đặt: nhận trả lời `agent.approve` từ điện thoại (requestId, allow).
    var agentAnswerSink: (@MainActor (String, Bool) -> Void)?
    /// AgentController đặt: nhận phản hồi `agent.help` khi người dùng can thiệp xong (requestId, resolved).
    var agentHelpSink: (@MainActor (String, Bool) -> Void)?
    private var promptedAccessibility = false
    private var acceptTask: Task<Void, Never>?
    private var sessions: [UUID: (session: HostSession, task: Task<Void, Never>)] = [:]

    init(security: SecurityCenter) { self.security = security }

    var currentListener: ControlListener? { listener }

    var isHosting: Bool {
        switch status {
        case .starting, .listening: true
        case .stopped, .failed: false
        }
    }

    var activeViewerCount: Int {
        sessionStates.values.filter { if case .streaming = $0 { true } else { false } }.count
    }

    func start() async {
        guard !isHosting else { return }
        status = .starting
        guard PermissionsCheck.hasScreenRecording else {
            PermissionsCheck.requestScreenRecording()
            status = .failed(String(localized: "Chưa có quyền Ghi màn hình. \(PermissionsCheck.settingsHint)"))
            return
        }
        if !AccessibilityPermission.isGranted, !promptedAccessibility {
            promptedAccessibility = true
            AccessibilityPermission.requestPrompt()
        }
        let encrypted = AppSecurity.current == .encrypted
        if encrypted, security.hostAuthenticator == nil {
            status = .failed(security.startupError ?? String(localized: "Không mở được kho khoá bảo mật"))
            return
        }
        await security.attach()
        let advertiser = BonjourAdvertiser(id: security.identityFingerprint.flatMap { encrypted ? $0 : nil } ?? HostIdentity.shortId, name: HostIdentity.displayName)
        let listener = ControlListener(
            security: AppSecurity.current, advertiser: advertiser, authenticator: encrypted ? security.hostAuthenticator : nil,
            allowTailscale: allowTailscale)
        do {
            let port = try await startListener(listener)
            self.listener = listener
            status = .listening(port: port)
            acceptTask = Task { [weak self] in
                for await connection in listener.connections { self?.admit(connection) }
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func setFitWindows(_ enabled: Bool) {
        fitWindows = enabled
        UserDefaults.standard.set(enabled, forKey: WindowFitter.enabledKey)
        if !enabled { windowFit.restoreNow() }
    }

    /// `persist: false` chỉ dành cho kiểm thử tự động (không ghi vào cài đặt người dùng).
    func setAllowTailscale(_ allowed: Bool, persist: Bool = true) {
        allowTailscale = allowed
        if persist { UserDefaults.standard.set(allowed, forKey: Self.allowTailscaleKey) }
        Task { await listener?.setAllowTailscale(allowed) }
    }

    /// Ngắt riêng một viewer đang xem (nút ngắt trong popover).
    func disconnect(sessionId: UUID) async {
        await sessions[sessionId]?.session.shutdown()
    }

    /// Các viewer đang xem, theo thứ tự ổn định, để popover liệt kê.
    var activeViewers: [(id: UUID, info: ViewerSessionInfo)] {
        sessionStates.compactMap { id, state in
            if case .streaming(_, _, _, let info) = state { (id, info) } else { nil }
        }.sorted { ($0.info.name, $0.id.uuidString) < ($1.info.name, $1.id.uuidString) }
    }

    func stop() async {
        acceptTask?.cancel()
        acceptTask = nil
        await listener?.stop()
        listener = nil
        let running = Array(sessions.values)
        for entry in running { await entry.session.shutdown() }
        for entry in running { await entry.task.value }
        sessions.removeAll()
        sessionStates.removeAll()
        status = .stopped
        await windowFit.restoreAfterSettle()
    }

    /// Gửi yêu cầu duyệt tới mọi viewer đang xem; trả lời đầu tiên (kể cả từ Mac) thắng.
    func broadcastAgentApproval(_ request: AgentApprove) async {
        for entry in Array(sessions.values) { await entry.session.sendAgentApproval(request) }
    }

    /// Gửi thông báo agent cần trợ giúp tới mọi viewer đang xem.
    func broadcastAgentHelp(_ help: AgentHelp) async {
        for entry in Array(sessions.values) { await entry.session.sendAgentHelp(help) }
    }

    private func startListener(_ listener: ControlListener) async throws -> UInt16 {
        do { return try await listener.start(port: Self.preferredPort) } catch { return try await listener.start(port: 0) }
    }

    private func admit(_ connection: ControlConnection) {
        let id = UUID()
        let session = HostSession(
            connection: connection, provider: VirtualDisplayProvider(), windowFit: windowFit, caps: [.h264, .hevc],
            report: { [weak self] state in Task { @MainActor in self?.update(id, state) } },
            onSecureInput: { [weak self] active in Task { @MainActor in self?.secureInputActive = active } },
            onAgentAnswer: { [weak self] requestId, allow in Task { @MainActor in self?.agentAnswerSink?(requestId, allow) } },
            onAgentHelp: { [weak self] requestId, resolved in Task { @MainActor in self?.agentHelpSink?(requestId, resolved) } },
            pasteboard: clipboardPasteboard, audioSettings: audioOptions.settings,
            permissionLookup: { [weak self] key in await self?.permissions(forViewerKey: key) }
        )
        sessions[id] = (session, Task { await session.run() })
    }

    /// Quyền hiện hành của viewer đã ghép (đọc lại mỗi lần để đổi quyền giữa phiên có hiệu lực ngay).
    private func permissions(forViewerKey key: [UInt8]) -> DevicePermissions? {
        security.pairedViewers.first { $0.publicKey == key }?.permissions
    }

    private func update(_ id: UUID, _ state: HostSessionState) {
        if case .ended(let reason) = state {
            log.notice("viewer session ended: \(reason, privacy: .public)")
            sessionStates[id] = nil
            sessions[id] = nil
        } else {
            sessionStates[id] = state
        }
    }
}

/// Định danh host hiển thị trên Bonjour: id ngắn ổn định (lưu UserDefaults) + tên Mac.
enum HostIdentity {
    private static let key = "xdesk.host.shortId"

    static var shortId: String {
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let fresh = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    static var displayName: String { Host.current().localizedName ?? "Mac" }
}
