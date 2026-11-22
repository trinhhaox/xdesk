import Foundation
import Testing
@testable import Xdesk

@Suite struct UnlockAttestationPrecheckTests {
    private let key = [UInt8](repeating: 4, count: 65)

    @Test func oldViewerWithoutAttestationNeverPassesEvenWithAStoredKey() {
        #expect(UnlockAttestationPrecheck.evaluate(attestationNegotiated: false, storedKey: key) == .viewerNeedsUpdate)
        #expect(UnlockAttestationPrecheck.evaluate(attestationNegotiated: false, storedKey: nil) == .viewerNeedsUpdate)
    }

    @Test func deviceWithoutEnrolledKeyFailsClosed() {
        #expect(UnlockAttestationPrecheck.evaluate(attestationNegotiated: true, storedKey: nil) == .keyNotEnrolled)
    }

    @Test func attestedDeviceWithKeyPasses() {
        #expect(UnlockAttestationPrecheck.evaluate(attestationNegotiated: true, storedKey: key) == .ok)
    }

    @Test func blockedStatesCarryAVietnameseMessage() {
        #expect(UnlockAttestationPrecheck.viewerNeedsUpdate.message?.contains("Cập nhật app Xdesk") == true)
        #expect(UnlockAttestationPrecheck.keyNotEnrolled.message != nil)
        #expect(UnlockAttestationPrecheck.ok.message == nil)
    }
}

@Suite struct LockScreenStateConsoleTests {
    @Test func lockedRequiresOnConsoleSession() {
        #expect(kCGSessionOnConsoleKey == "kCGSSessionOnConsoleKey")
        let locked: [String: Any] = ["CGSSessionScreenIsLocked": true, kCGSessionOnConsoleKey: true]
        #expect(LockScreenState.make(session: locked, displayAwake: true) == LockScreenState(locked: true, displayAwake: true))
    }

    @Test func lockedSessionThatIsNotOnConsoleIsNotTreatedAsLocked() {
        let switchedAway: [String: Any] = ["CGSSessionScreenIsLocked": true, kCGSessionOnConsoleKey: false]
        #expect(LockScreenState.make(session: switchedAway, displayAwake: true).locked == false)
        #expect(LockScreenState.make(session: ["CGSSessionScreenIsLocked": true], displayAwake: true).locked == false)
        #expect(LockScreenState.make(session: nil, displayAwake: true).locked == false)
    }

    @Test func lockFallbackReportsFailureWithGuidance() {
        let sleptOnly = RemoteLockExecutor.result(for: .displaySleptOnly)
        #expect(!sleptOnly.ok && sleptOnly.message.contains("Yêu cầu mật khẩu"))
        #expect(RemoteLockExecutor.result(for: .locked) == (true, "Đã khoá Mac"))
    }

    @Test func rateLimitsSurviveReconnectAndAreIndependentPerKindAndDevice() {
        let limits = UnlockRateLimits()
        let a = [UInt8](repeating: 1, count: 32), b = [UInt8](repeating: 2, count: 32)
        let results = (0..<4).map { _ in limits.allow(.challenge, deviceKey: a, now: 100) }
        #expect(results == [true, true, true, false])
        #expect(limits.allow(.signed, deviceKey: a, now: 100))
        #expect(limits.allow(.challenge, deviceKey: b, now: 100))
        #expect(!limits.allow(.challenge, deviceKey: a, now: 120))
        #expect(limits.allow(.challenge, deviceKey: a, now: 161))
        let keys = (0..<11).map { _ in limits.allow(.key, deviceKey: a, now: 200) }
        #expect(keys.filter { $0 }.count == 10)
    }
}
