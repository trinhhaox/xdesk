import AppKit
import Foundation
import os
import XdeskAgent
import XdeskWire

/// Gom mọi thành phần của agent: màn hình, quyền điều khiển, luật app, banner, giám sát người thật, phím tắt.
/// Các tool giữ tham chiếu tới đối tượng này (MainActor nên Sendable) và gọi qua `await`.
@MainActor
final class AgentRuntime {
    static let log = Logger(subsystem: "vn.xox.xdesk", category: "agent-runtime")

    let settings: AgentSettings
    let host: HostController
    let displays = AgentDisplayManager()
    let refs = UiRefTable()
    let poster = AgentEventPoster()
    let approvals: ApprovalCoordinator
    let arbiter: ControlArbiter
    let gate: AppGate
    private(set) var control = ControlSnapshot()
    private(set) var inputMonitorActive = false
    private(set) var clientName = "Agent AI"
    var banner: AgentBanner?
    private var monitor: HumanInputMonitor?
    private let hotkey = StopHotkey()
    private var idleTask: Task<Void, Never>?
    private var changes: AsyncStream<ControlSnapshot>.Continuation?
    private var pendingHelpRequests: [String: CheckedContinuation<Bool, Never>] = [:]

    init(host: HostController, settings: AgentSettings) {
        self.host = host
        self.settings = settings
        let approvals = ApprovalCoordinator(host: host)
        self.approvals = approvals
        let (stream, continuation) = AsyncStream<ControlSnapshot>.makeStream()
        changes = continuation
        arbiter = ControlArbiter(prompter: approvals, idleTimeout: Double(settings.idleSeconds), onChange: { continuation.yield($0) })
        gate = AppGate(policy: { await MainActor.run { settings.policy } }, prompter: approvals)
        host.agentAnswerSink = { [approvals] id, allow in approvals.resolve(id, allow: allow) }
        host.agentHelpSink = { [weak self] id, resolved in self?.resolveUserHelp(requestId: id, resolved: resolved) }
        settings.onIdleChange = { [arbiter] seconds in Task { await arbiter.setIdleTimeout(Double(seconds)) } }
        banner = AgentBanner(
            onPause: { [weak self] in self?.pause("người dùng bấm Tạm dừng") },
            onResume: { [arbiter] in Task { await arbiter.resume() } },
            onStop: { [weak self] in self?.stop("người dùng bấm Dừng") })
        monitor = HumanInputMonitor(
            displayBounds: { [weak self] in MainActor.assumeIsolated { self?.displays.bounds } },
            ignoredRects: { [weak self] in MainActor.assumeIsolated { self?.banner?.cgFrame.map { [$0] } ?? [] } },
            onHumanInput: { [weak self] in Task { @MainActor in self?.pause("người dùng thao tác trên màn hình agent") } })
        Task { @MainActor [weak self] in
            for await snapshot in stream { self?.applyControl(snapshot) }
        }
    }

    func setClientName(_ name: String) { clientName = name.isEmpty ? "Agent AI" : name }

    func pause(_ reason: String) { Task { await arbiter.pause(reason: reason) } }

    func stop(_ reason: String) { Task { await arbiter.end(reason: reason) } }

    /// Bật phím tắt dừng toàn cục khi MCP chạy.
    func activate() {
        if !hotkey.register({ [weak self] in self?.pause("người dùng nhấn \(StopHotkey.label)") }) {
            Self.log.error("phím tắt dừng không khả dụng")
        }
    }

    func shutdown() {
        hotkey.unregister()
        stop("MCP đã tắt")
        monitor?.stop()
        banner?.hide()
        displays.destroy()
        refs.replace(with: [])
    }

    private func applyControl(_ snapshot: ControlSnapshot) {
        let previous = control.phase
        control = snapshot
        banner?.update(snapshot, displayID: displays.displayID)
        switch snapshot.phase {
        case .granted, .paused:
            if monitor?.isRunning != true { inputMonitorActive = monitor?.start() ?? false }
            startIdleTicker()
        case .none, .requested:
            monitor?.stop()
            idleTask?.cancel()
            idleTask = nil
            if previous == .granted || previous == .paused {
                Task { await gate.resetSession() }
            }
        }
    }

    private func startIdleTicker() {
        guard idleTask == nil else { return }
        idleTask = Task { [arbiter] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await arbiter.tickIdle()
            }
        }
    }

    func status() async -> AgentStatus { AgentStatus(display: displays.geometry, control: await arbiter.snapshot) }

    // MARK: Hỗ trợ cho tool

    struct DisplayContext {
        let id: CGDirectDisplayID
        let bounds: CGRect
        let geometry: AgentDisplayGeometry
    }

    func requireDisplay() -> Result<DisplayContext, AgentToolFailure> {
        guard let id = displays.displayID, let bounds = displays.bounds, let geometry = displays.geometry else {
            return .failure(AgentToolFailure("Chưa có màn hình agent. Hãy gọi xdesk_request_control trước."))
        }
        return .success(DisplayContext(id: id, bounds: bounds, geometry: geometry))
    }

    /// Đổi toạ độ màn hình agent sang toàn cục; nil nếu nằm ngoài màn hình agent.
    func globalPoint(x: Double, y: Double, in context: DisplayContext) -> CGPoint? {
        context.geometry.contains(x: x, y: y) ? CGPoint(x: context.bounds.minX + x, y: context.bounds.minY + y) : nil
    }

    /// Kiểm luật app cho cửa sổ dưới điểm toàn cục. nil = được phép.
    func checkApp(under point: CGPoint) async -> String? {
        guard let app = AgentTargeting.appUnder(point: point) else { return nil }
        return await verdict(app)
    }

    /// Phím/chữ chỉ được gõ khi cửa sổ đang focus nằm trên màn hình agent, để không tràn sang màn hình của người dùng.
    func checkFocused(in context: DisplayContext) async -> String? {
        guard let focus = AgentTargeting.focused(), let frame = focus.windowFrame,
              context.bounds.contains(CGPoint(x: frame.midX, y: frame.midY)) else {
            return "Cửa sổ đang focus không nằm trên màn hình agent. Hãy xdesk_pointer click vào cửa sổ trên màn hình agent trước khi gõ/nhấn phím."
        }
        return await verdict(focus.app)
    }

    func requestUserHelp(reason: String, timeoutSeconds: Int = 120) async -> Bool {
        let requestId = UUID().uuidString
        let message = AgentHelp.request(requestId: requestId, reason: reason)
        await host.broadcastAgentHelp(message)

        return await withCheckedContinuation { continuation in
            pendingHelpRequests[requestId] = continuation
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                await MainActor.run { [weak self] in
                    if let c = self?.pendingHelpRequests.removeValue(forKey: requestId) {
                        c.resume(returning: false)
                    }
                }
            }
        }
    }

    func resolveUserHelp(requestId: String, resolved: Bool) {
        guard let continuation = pendingHelpRequests.removeValue(forKey: requestId) else { return }
        continuation.resume(returning: resolved)
    }

    private func verdict(_ app: AppIdentity) async -> String? {
        if case .refused(let reason) = await gate.evaluate(bundleId: app.bundleId, displayName: app.name) { return reason }
        return nil
    }
}

struct AgentToolFailure: Error, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
}
