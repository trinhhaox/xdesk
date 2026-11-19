import Foundation
import Testing
@testable import XdeskAgent

private final class CountingPrompter: ApprovalPrompting, @unchecked Sendable {
    private let lock = NSLock()
    private var asked = 0
    let answer: Bool
    init(answer: Bool) { self.answer = answer }
    var count: Int { lock.withLock { asked } }
    func requestApproval(_ request: ApprovalRequest) async -> Bool { lock.withLock { asked += 1 }; return answer }
}

@Suite struct AppPolicyTests {
    @Test func defaultsForbidSensitiveApps() {
        let policy = AppPolicy.defaults
        #expect(policy.rule(for: "com.apple.Terminal") == .never)
        #expect(policy.rule(for: "com.apple.keychainaccess") == .never)
        #expect(policy.rule(for: "com.apple.systempreferences") == .never)
        #expect(policy.rule(for: "com.apple.TextEdit") == .ask)
        #expect(policy.rule(for: "COM.APPLE.TERMINAL") == .never)
    }

    @Test func systemSettingsUrlsAreRecognised() {
        #expect(AppPolicy.isSystemSettingsURL(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!))
        #expect(!AppPolicy.isSystemSettingsURL(URL(string: "https://example.com")!))
    }

    @Test func policyIsCodable() throws {
        var policy = AppPolicy.defaults
        policy.rules["com.apple.TextEdit"] = .allow
        let decoded = try JSONDecoder().decode(AppPolicy.self, from: JSONEncoder().encode(policy))
        #expect(decoded == policy)
    }

    @Test func gateRefusesNeverWithoutAsking() async {
        let prompter = CountingPrompter(answer: true)
        let gate = AppGate(policy: { .defaults }, prompter: prompter)
        guard case .refused(let reason) = await gate.evaluate(bundleId: "com.apple.Terminal", displayName: "Terminal") else { Issue.record("phải bị cấm"); return }
        #expect(reason.contains("never"))
        #expect(prompter.count == 0)
    }

    @Test func gateAsksOncePerSessionThenResets() async {
        let prompter = CountingPrompter(answer: true)
        let gate = AppGate(policy: { .defaults }, prompter: prompter)
        #expect(await gate.evaluate(bundleId: "com.apple.TextEdit", displayName: "TextEdit") == .allowed)
        #expect(await gate.evaluate(bundleId: "com.apple.TextEdit", displayName: "TextEdit") == .allowed)
        #expect(prompter.count == 1)
        await gate.resetSession()
        _ = await gate.evaluate(bundleId: "com.apple.TextEdit", displayName: "TextEdit")
        #expect(prompter.count == 2)
    }

    @Test func gateHonoursAllowAndUserDenial() async {
        var policy = AppPolicy.defaults
        policy.rules["com.apple.TextEdit"] = .allow
        let snapshot = policy
        let allowGate = AppGate(policy: { snapshot }, prompter: CountingPrompter(answer: false))
        #expect(await allowGate.evaluate(bundleId: "com.apple.TextEdit", displayName: "TextEdit") == .allowed)
        let denyGate = AppGate(policy: { .defaults }, prompter: CountingPrompter(answer: false))
        guard case .refused = await denyGate.evaluate(bundleId: "com.apple.Safari", displayName: "Safari") else { Issue.record("người dùng từ chối"); return }
    }
}
