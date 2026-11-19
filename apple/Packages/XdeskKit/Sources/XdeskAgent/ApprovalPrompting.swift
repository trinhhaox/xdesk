import Foundation

public struct ApprovalRequest: Sendable, Equatable {
    public var id: String
    public var agentName: String
    public var summary: String
    public var expiresAt: Date

    public init(id: String, agentName: String, summary: String, expiresAt: Date) {
        self.id = id; self.agentName = agentName; self.summary = summary; self.expiresAt = expiresAt
    }
}

/// Hỏi người dùng (hộp thoại trên Mac + điện thoại, cái nào trả lời trước thắng). Phải thoát nhanh khi task bị huỷ.
public protocol ApprovalPrompting: Sendable {
    func requestApproval(_ request: ApprovalRequest) async -> Bool
}

/// Chạy prompter song song với đồng hồ hết hạn; hết hạn = từ chối.
enum ApprovalRace {
    static func run(_ prompter: any ApprovalPrompting, _ request: ApprovalRequest, timeout: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await prompter.requestApproval(request) }
            group.addTask {
                do { try await Task.sleep(for: timeout) } catch { return false }
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}
