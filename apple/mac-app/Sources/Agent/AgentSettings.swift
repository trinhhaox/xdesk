import Foundation
import Observation
import XdeskAgent

/// Cài đặt agent lưu trong UserDefaults: luật theo app và thời gian im lặng trước khi tự nhả quyền.
@MainActor
@Observable
final class AgentSettings {
    static let idleRange = 15...1800
    private static let policyKey = "mcp.appPolicy"
    private static let idleKey = "mcp.idleSeconds"

    var idleSeconds: Int {
        didSet {
            idleSeconds = min(max(idleSeconds, Self.idleRange.lowerBound), Self.idleRange.upperBound)
            defaults.set(idleSeconds, forKey: Self.idleKey)
            onIdleChange?(idleSeconds)
        }
    }
    var policy: AppPolicy {
        didSet {
            guard let data = try? JSONEncoder().encode(policy) else { return }
            defaults.set(data, forKey: Self.policyKey)
        }
    }
    @ObservationIgnored var onIdleChange: (@MainActor (Int) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.integer(forKey: Self.idleKey)
        idleSeconds = Self.idleRange.contains(stored) ? stored : 120
        policy = defaults.data(forKey: Self.policyKey).flatMap { try? JSONDecoder().decode(AppPolicy.self, from: $0) } ?? .defaults
    }
}
