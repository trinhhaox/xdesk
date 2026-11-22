import Foundation
import Testing
@testable import Xdesk

@Suite struct RemoteLockUnlockFlowTests {
    private func states(_ list: [LockScreenState]) -> () -> LockScreenState {
        var queue = list
        return { queue.count > 1 ? queue.removeFirst() : queue[0] }
    }

    private let locked = LockScreenState(locked: true, displayAwake: true)
    private let asleep = LockScreenState(locked: true, displayAwake: false)
    private let open = LockScreenState(locked: false, displayAwake: true)

    @Test func waitsForDisplayToWakeAndSettleBeforeTyping() async {
        let result = await LockScreenWait.wait(probe: states([asleep, asleep, locked, locked, locked]), sleep: { _ in })
        #expect(result == .ready)
    }

    @Test func unlockedMacOnlyWakes() async {
        #expect(await LockScreenWait.wait(probe: states([asleep, open]), sleep: { _ in }) == .notLocked)
    }

    @Test func displayThatNeverWakesTimesOut() async {
        let result = await LockScreenWait.wait(probe: { asleep }, timeout: .milliseconds(600), sleep: { _ in })
        #expect(result == .timedOut)
    }

    @Test func flickeringLockStateResetsStability() async {
        let result = await LockScreenWait.wait(
            probe: states([locked, locked, asleep, locked, locked, locked]), sleep: { _ in })
        #expect(result == .ready)
    }

    @Test func typingStopsWhenMacUnlocksMidway() {
        let password = Array(repeating: UInt16(0x61), count: 45)
        var checks = 0
        var posted: [[UInt16]] = []
        var returned = false
        let outcome = RemoteUnlockExecutor.typeWhileLocked(
            password, isLocked: { checks += 1; return checks <= 2 },
            post: { posted.append($0) }, pressReturn: { returned = true })
        #expect(!outcome.ok)
        #expect(posted.count == 2)
        #expect(!returned)
    }

    @Test func typingWholePasswordThenPressesReturn() {
        let password = Array(repeating: UInt16(0x61), count: 45)
        var posted: [[UInt16]] = []
        var returned = false
        let outcome = RemoteUnlockExecutor.typeWhileLocked(
            password, isLocked: { true }, post: { posted.append($0) }, pressReturn: { returned = true })
        #expect(outcome.ok)
        #expect(posted.map(\.count) == [20, 20, 5])
        #expect(returned)
    }

    @Test func transcodesUtf8PasswordWithoutString() {
        #expect(PasswordTranscoder.utf16(fromUTF8: Array("Mật-khẩu😀".utf8)) == Array("Mật-khẩu😀".utf16))
        #expect(PasswordTranscoder.utf16(fromUTF8: [0xFF, 0xFE]) == nil)
    }

    @Test func lockTriesEachMethodThenFallsBackToDisplaySleep() async {
        var calls: [String] = []
        var slept = 0
        var lockedAfter = false
        let ok = await RemoteLockExecutor.lockScreen(
            isLocked: { lockedAfter },
            attempts: [{ calls.append("api"); return true }, { calls.append("keys"); lockedAfter = true; return true }],
            sleepDisplay: { slept += 1 }, sleep: { _ in })
        #expect(ok == .locked)
        #expect(calls == ["api", "keys"])
        #expect(slept == 0)

        calls = []
        let fallback = await RemoteLockExecutor.lockScreen(
            isLocked: { false },
            attempts: [{ calls.append("api"); return false }, { calls.append("keys"); return true }],
            sleepDisplay: { slept += 1 }, sleep: { _ in })
        #expect(fallback == .displaySleptOnly)
        #expect(calls == ["api", "keys"])
        #expect(slept == 1)
    }

    @Test func alreadyLockedSkipsAllMethods() async {
        var called = false
        let outcome = await RemoteLockExecutor.lockScreen(
            isLocked: { true }, attempts: [{ called = true; return true }], sleepDisplay: { called = true }, sleep: { _ in })
        #expect(outcome == .locked)
        #expect(!called)
    }
}
