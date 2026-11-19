import Foundation

public enum ControlPhase: String, Sendable, Equatable { case none, requested, granted, paused }

/// Ảnh chụp trạng thái quyền điều khiển cho banner, `xdesk_status` và menu.
public struct ControlSnapshot: Sendable, Equatable {
    public var phase: ControlPhase = .none
    public var holder: String?
    /// Lý do tạm dừng/nhả gần nhất (hiện trên banner).
    public var reason: String?

    public init(phase: ControlPhase = .none, holder: String? = nil, reason: String? = nil) {
        self.phase = phase; self.holder = holder; self.reason = reason
    }

    public var summary: String {
        switch phase {
        case .none: "không có"
        case .requested: "đang chờ người dùng duyệt (\(holder ?? "agent"))"
        case .granted: "\(holder ?? "agent") (đang hoạt động)"
        case .paused: "\(holder ?? "agent") (tạm dừng\(reason.map { ": \($0)" } ?? ""))"
        }
    }
}

public enum ControlAuthorization: Sendable, Equatable {
    case allowed
    case denied(String)
}

public enum ControlOutcome: Sendable, Equatable {
    case granted
    case denied(String)
}

/// Máy trạng thái quyền điều khiển: none → requested → granted ⇄ paused. Chỉ một agent giữ quyền tại một thời điểm.
/// Thời gian nhận từ `now` để test được tự nhả khi im lặng; mọi lời gọi tool đều đi qua `authorize()` (không I/O nên < 1 ms).
public actor ControlArbiter {
    public static let pausedMessage = "control paused: người dùng đã tạm dừng agent, hãy chờ họ bấm Tiếp tục"

    private let prompter: any ApprovalPrompting
    private let approvalTimeout: Duration
    private let now: @Sendable () -> Date
    private let onChange: @Sendable (ControlSnapshot) -> Void
    private var idleTimeout: TimeInterval
    private var state = ControlSnapshot()
    private var lastActivity = Date.distantPast
    private var counter = 0

    public init(
        prompter: any ApprovalPrompting, idleTimeout: TimeInterval = 120, approvalTimeout: Duration = .seconds(60),
        now: @escaping @Sendable () -> Date = { Date() }, onChange: @escaping @Sendable (ControlSnapshot) -> Void = { _ in }
    ) {
        self.prompter = prompter; self.idleTimeout = idleTimeout; self.approvalTimeout = approvalTimeout
        self.now = now; self.onChange = onChange
    }

    public var snapshot: ControlSnapshot { state }

    public func setIdleTimeout(_ seconds: TimeInterval) { idleTimeout = max(5, seconds) }

    public func request(agentName: String, reason: String) async -> ControlOutcome {
        switch state.phase {
        case .granted: return .granted
        case .requested: return .denied("đang chờ người dùng duyệt một yêu cầu khác")
        case .paused: return .denied(Self.pausedMessage)
        case .none: break
        }
        counter += 1
        let expires = now().addingTimeInterval(Double(approvalTimeout.components.seconds))
        let request = ApprovalRequest(id: "req-\(counter)-\(UUID().uuidString.prefix(8))", agentName: agentName, summary: reason, expiresAt: expires)
        set(ControlSnapshot(phase: .requested, holder: agentName))
        let allowed = await ApprovalRace.run(prompter, request, timeout: approvalTimeout)
        guard state.phase == .requested else { return .denied("yêu cầu đã bị huỷ") }
        guard allowed else {
            set(ControlSnapshot())
            return .denied("người dùng từ chối hoặc không trả lời kịp")
        }
        lastActivity = now()
        set(ControlSnapshot(phase: .granted, holder: agentName))
        return .granted
    }

    /// Cổng chung của mọi tool (trừ status/request/end). Cập nhật mốc hoạt động để tính tự nhả.
    public func authorize() -> ControlAuthorization {
        switch state.phase {
        case .none: return .denied(state.reason ?? "chưa được cấp quyền điều khiển, hãy gọi xdesk_request_control")
        case .requested: return .denied("đang chờ người dùng duyệt")
        case .paused: return .denied(Self.pausedMessage)
        case .granted:
            if releaseIfIdle() { return .denied(state.reason ?? "quyền đã hết hạn") }
            lastActivity = now()
            return .allowed
        }
    }

    /// Gọi định kỳ để banner biến mất đúng lúc khi agent im lặng.
    @discardableResult
    public func tickIdle() -> Bool { state.phase == .granted && releaseIfIdle() }

    public func pause(reason: String) {
        guard state.phase == .granted else { return }
        set(ControlSnapshot(phase: .paused, holder: state.holder, reason: reason))
    }

    public func resume() {
        guard state.phase == .paused else { return }
        lastActivity = now()
        set(ControlSnapshot(phase: .granted, holder: state.holder))
    }

    /// Nhả quyền (agent gọi end_control, người dùng bấm Dừng, hoặc tắt MCP). Trả về true nếu có quyền đang giữ/chờ.
    @discardableResult
    public func end(reason: String? = nil) -> Bool {
        guard state.phase != .none else { return false }
        set(ControlSnapshot(phase: .none, reason: reason))
        return true
    }

    private func releaseIfIdle() -> Bool {
        guard now().timeIntervalSince(lastActivity) > idleTimeout else { return false }
        set(ControlSnapshot(phase: .none, reason: "quyền đã tự nhả do agent im lặng quá \(Int(idleTimeout)) giây, hãy xin lại"))
        return true
    }

    private func set(_ new: ControlSnapshot) {
        state = new
        onChange(new)
    }
}
