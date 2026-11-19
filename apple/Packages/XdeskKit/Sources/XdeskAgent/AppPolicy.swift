import Foundation

public enum AppRule: String, Codable, Sendable, CaseIterable { case allow, ask, never }

/// Luật theo bundle id. Mặc định `ask`; `never` cho các app có thể lộ bí mật hoặc đổi quyền hệ thống.
public struct AppPolicy: Codable, Sendable, Equatable {
    public var rules: [String: AppRule]
    public var fallback: AppRule

    public static let systemSettingsId = "com.apple.systempreferences"
    public static let defaults = AppPolicy(rules: [
        systemSettingsId: .never,        // cả app, vì không biết đang ở mục Quyền riêng tư nào
        "com.apple.keychainaccess": .never,
        "com.apple.Terminal": .never,
    ])

    public init(rules: [String: AppRule] = [:], fallback: AppRule = .ask) {
        self.rules = rules; self.fallback = fallback
    }

    public func rule(for bundleId: String) -> AppRule {
        let key = bundleId.lowercased()
        return rules.first { $0.key.lowercased() == key }?.value ?? fallback
    }

    /// Mở thẳng một mục Cài đặt hệ thống bằng URL cũng bị chặn, kể cả khi người dùng đã đổi luật của app.
    public static func isSystemSettingsURL(_ url: URL) -> Bool { url.scheme?.lowercased() == "x-apple.systempreferences" }
}

public enum AppVerdict: Sendable, Equatable {
    case allowed
    case refused(String)
}

/// Áp luật: `never` từ chối, `allow` cho qua, `ask` hỏi người dùng một lần cho mỗi app trong một lượt cấp quyền.
public actor AppGate {
    private let policy: @Sendable () async -> AppPolicy
    private let prompter: any ApprovalPrompting
    private let timeout: Duration
    private var approved: Set<String> = []

    public init(policy: @escaping @Sendable () async -> AppPolicy, prompter: any ApprovalPrompting, timeout: Duration = .seconds(60)) {
        self.policy = policy; self.prompter = prompter; self.timeout = timeout
    }

    public func evaluate(bundleId: String, displayName: String) async -> AppVerdict {
        switch await policy().rule(for: bundleId) {
        case .never: return .refused("luật app: \(displayName) (\(bundleId)) bị cấm (never)")
        case .allow: return .allowed
        case .ask:
            let key = bundleId.lowercased()
            if approved.contains(key) { return .allowed }
            let request = ApprovalRequest(
                id: "app-\(UUID().uuidString.prefix(8))", agentName: "Agent", summary: "Cho phép agent dùng ứng dụng \(displayName)?",
                expiresAt: Date().addingTimeInterval(Double(timeout.components.seconds)))
            guard await ApprovalRace.run(prompter, request, timeout: timeout) else {
                return .refused("người dùng không cho phép agent dùng \(displayName)")
            }
            approved.insert(key)
            return .allowed
        }
    }

    /// Gọi khi quyền điều khiển kết thúc: lần sau hỏi lại.
    public func resetSession() { approved.removeAll() }
}
