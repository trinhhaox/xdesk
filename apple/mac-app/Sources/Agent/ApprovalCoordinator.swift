import AppKit
import SwiftUI
import XdeskAgent
import XdeskWire

/// Hỏi người dùng trên Mac và (nếu có viewer đang xem) cả điện thoại cùng lúc; trả lời đầu tiên thắng, cửa sổ còn lại đóng.
@MainActor
final class ApprovalCoordinator: ApprovalPrompting {
    private let host: HostController
    private var pending: [String: CheckedContinuation<Bool, Never>] = [:]
    private var windows: [String: SecureWindow] = [:]
    #if DEBUG
    /// Chỉ Debug (`--auto-approve-agent`): bỏ qua mọi hộp thoại duyệt để kiểm thử tự động.
    var autoApprove = false
    #endif

    init(host: HostController) { self.host = host }

    nonisolated func requestApproval(_ request: ApprovalRequest) async -> Bool {
        await withTaskCancellationHandler {
            await ask(request)
        } onCancel: {
            Task { @MainActor in self.resolve(request.id, allow: false) }
        }
    }

    /// Trả lời từ Mac hoặc điện thoại; trả lời muộn/không khớp bị bỏ.
    func resolve(_ id: String, allow: Bool) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        windows.removeValue(forKey: id)?.close()
        continuation.resume(returning: allow)
    }

    private func ask(_ request: ApprovalRequest) async -> Bool {
        #if DEBUG
        if autoApprove { return true }
        #endif
        let expiresMs = Int64(request.expiresAt.timeIntervalSince1970 * 1000)
        let message = AgentApprove.request(requestId: String(request.id.prefix(64)), agentName: String(request.agentName.prefix(100)),
                                           summary: String(request.summary.prefix(400)), expiresAt: expiresMs)
        return await withCheckedContinuation { continuation in
            pending[request.id] = continuation
            let window = SecureWindow(title: String(localized: "Agent AI xin quyền"), floating: true, onClose: { [weak self] in self?.resolve(request.id, allow: false) },
                                      content: ApprovalView(request: request) { [weak self] allow in self?.resolve(request.id, allow: allow) })
            windows[request.id] = window
            window.show()
            Task { await host.broadcastAgentApproval(message) }
        }
    }
}

private struct ApprovalView: View {
    let request: ApprovalRequest
    let answer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(request.agentName) muốn điều khiển màn hình agent").font(.headline)
            Text(request.summary).font(.body).textSelection(.enabled)
            Text("Agent chỉ làm việc trên màn hình ảo \"Xdesk Agent\". Bạn có thể tạm dừng bất kỳ lúc nào bằng banner hoặc ⌃⌥⌘.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Tự từ chối sau \(max(1, Int(request.expiresAt.timeIntervalSinceNow))) giây.").font(.footnote).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Từ chối") { answer(false) }.keyboardShortcut(.cancelAction)
                Button("Cho phép") { answer(true) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
