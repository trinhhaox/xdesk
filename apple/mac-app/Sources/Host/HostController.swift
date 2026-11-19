import Foundation
import Observation
import os
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

    private let log = Logger(subsystem: "vn.xox.xdesk", category: "host-controller")
    private let security: SecurityCenter
    private var listener: ControlListener?
    private var promptedAccessibility = false
    private var acceptTask: Task<Void, Never>?
    private var sessions: [UUID: (session: HostSession, task: Task<Void, Never>)] = [:]

    init(security: SecurityCenter) { self.security = security }

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
            status = .failed("Chưa có quyền Ghi màn hình. \(PermissionsCheck.settingsHint)")
            return
        }
        if !AccessibilityPermission.isGranted, !promptedAccessibility {
            promptedAccessibility = true
            AccessibilityPermission.requestPrompt()
        }
        let encrypted = AppSecurity.current == .encrypted
        if encrypted, security.hostAuthenticator == nil {
            status = .failed(security.startupError ?? "Không mở được kho khoá bảo mật")
            return
        }
        await security.attach()
        let advertiser = BonjourAdvertiser(id: security.identityFingerprint.flatMap { encrypted ? $0 : nil } ?? HostIdentity.shortId, name: HostIdentity.displayName)
        let listener = ControlListener(
            security: AppSecurity.current, advertiser: advertiser, authenticator: encrypted ? security.hostAuthenticator : nil)
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
    }

    private func startListener(_ listener: ControlListener) async throws -> UInt16 {
        do { return try await listener.start(port: Self.preferredPort) } catch { return try await listener.start(port: 0) }
    }

    private func admit(_ connection: ControlConnection) {
        let id = UUID()
        let session = HostSession(
            connection: connection, provider: VirtualDisplayProvider(), caps: [.h264, .hevc],
            report: { [weak self] state in Task { @MainActor in self?.update(id, state) } },
            onSecureInput: { [weak self] active in Task { @MainActor in self?.secureInputActive = active } }
        )
        sessions[id] = (session, Task { await session.run() })
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
