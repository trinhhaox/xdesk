import Foundation
import XdeskTransport
import XdeskWire

/// Host xin duyệt quyền điều khiển cho agent AI; UI hiện hộp thoại Cho phép / Từ chối.
public struct AgentApprovalRequest: Sendable, Equatable, Identifiable {
    public var id: String
    public var agentName: String
    public var summary: String
    /// Giờ viewer (đã quy đổi từ giờ host) mà yêu cầu hết hạn.
    public var expiresAt: Date
}

extension ViewerSession {
    func receiveAgentApproval(_ approve: AgentApprove) {
        let hostNow = hostNowMs() ?? ClockSync.wallClockMs()
        let remainingMs = (approve.expiresAt ?? 0) - hostNow
        guard remainingMs > 0 else { return }
        let request = AgentApprovalRequest(
            id: approve.requestId, agentName: approve.agentName ?? "Agent AI", summary: approve.summary ?? "",
            expiresAt: Date().addingTimeInterval(Double(remainingMs) / 1000))
        pendingAgentApproval = request
        tasks.append(Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(remainingMs))
            guard !Task.isCancelled, let self, self.pendingAgentApproval?.id == request.id else { return }
            self.pendingAgentApproval = nil
        })
    }

    /// Gửi trả lời về host rồi đóng hộp thoại. Trả lời muộn hoặc sau khi Mac đã duyệt sẽ bị host bỏ qua.
    public func answerAgentApproval(allow: Bool) async {
        guard let request = pendingAgentApproval else { return }
        pendingAgentApproval = nil
        guard let connection else { return }
        do { _ = try await connection.send(.agentApprove(.response(requestId: request.id, allow: allow))) }
        catch { log.error("gửi agent.approve lỗi: \(error.localizedDescription, privacy: .public)") }
    }
}
