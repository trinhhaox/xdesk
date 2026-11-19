import Foundation
import Testing
@testable import XdeskAgent

/// Prompter giả: trả lời cố định hoặc treo tới khi bị huỷ.
struct FakePrompter: ApprovalPrompting {
    enum Mode: Sendable { case allow, deny, hang }
    var mode: Mode
    func requestApproval(_ request: ApprovalRequest) async -> Bool {
        switch mode {
        case .allow: return true
        case .deny: return false
        case .hang:
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
            return false
        }
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000)
    func now() -> Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

private func makeArbiter(_ mode: FakePrompter.Mode = .allow, clock: TestClock = TestClock(), timeout: Duration = .seconds(5)) -> ControlArbiter {
    ControlArbiter(prompter: FakePrompter(mode: mode), idleTimeout: 120, approvalTimeout: timeout, now: { clock.now() })
}

@Suite struct ControlArbiterTests {
    @Test func toolsAreDeniedUntilGranted() async {
        let arbiter = makeArbiter()
        guard case .denied(let reason) = await arbiter.authorize() else { Issue.record("phải bị từ chối"); return }
        #expect(reason.contains("xdesk_request_control"))
        #expect(await arbiter.request(agentName: "Claude", reason: "mở TextEdit") == .granted)
        #expect(await arbiter.authorize() == .allowed)
        #expect(await arbiter.snapshot.holder == "Claude")
    }

    @Test func userDenialLeavesNoHolder() async {
        let arbiter = makeArbiter(.deny)
        guard case .denied = await arbiter.request(agentName: "Claude", reason: "x") else { Issue.record("phải bị từ chối"); return }
        #expect(await arbiter.snapshot.phase == .none)
    }

    @Test func approvalTimeoutDenies() async {
        let arbiter = makeArbiter(.hang, timeout: .milliseconds(80))
        guard case .denied = await arbiter.request(agentName: "Claude", reason: "x") else { Issue.record("hết hạn phải từ chối"); return }
        #expect(await arbiter.snapshot.phase == .none)
    }

    @Test func idleReleaseAfterTimeout() async {
        let clock = TestClock()
        let arbiter = makeArbiter(clock: clock)
        _ = await arbiter.request(agentName: "A", reason: "x")
        clock.advance(100)
        #expect(await arbiter.authorize() == .allowed)   // hoạt động làm mới mốc im lặng
        clock.advance(121)
        #expect(await arbiter.tickIdle())
        #expect(await arbiter.snapshot.phase == .none)
        guard case .denied(let reason) = await arbiter.authorize() else { Issue.record("phải hết quyền"); return }
        #expect(reason.contains("im lặng"))
    }

    @Test func idleTimeoutIsConfigurable() async {
        let clock = TestClock()
        let arbiter = makeArbiter(clock: clock)
        await arbiter.setIdleTimeout(30)
        _ = await arbiter.request(agentName: "A", reason: "x")
        clock.advance(31)
        guard case .denied = await arbiter.authorize() else { Issue.record("30 s phải đủ để nhả"); return }
    }

    @Test func pauseBlocksNextToolImmediatelyAndResumeRestores() async {
        let arbiter = makeArbiter()
        _ = await arbiter.request(agentName: "A", reason: "x")
        await arbiter.pause(reason: "người dùng chạm chuột")
        let started = ContinuousClock.now
        let verdict = await arbiter.authorize()
        #expect(ContinuousClock.now - started < .milliseconds(100))
        #expect(verdict == .denied(ControlArbiter.pausedMessage))
        #expect(ControlArbiter.pausedMessage.hasPrefix("control paused"))
        guard case .denied = await arbiter.request(agentName: "A", reason: "again") else { Issue.record("agent không tự tiếp tục được"); return }
        await arbiter.resume()
        #expect(await arbiter.authorize() == .allowed)
    }

    @Test func endReleasesAndIsIdempotent() async {
        let arbiter = makeArbiter()
        #expect(await arbiter.end() == false)
        _ = await arbiter.request(agentName: "A", reason: "x")
        #expect(await arbiter.end(reason: "người dùng bấm Dừng"))
        #expect(await arbiter.snapshot.phase == .none)
        #expect(await arbiter.end() == false)
    }

    @Test func secondRequestWhileWaitingIsRefused() async {
        let arbiter = makeArbiter(.hang, timeout: .seconds(2))
        async let first = arbiter.request(agentName: "A", reason: "x")
        try? await Task.sleep(for: .milliseconds(50))
        guard case .denied(let reason) = await arbiter.request(agentName: "B", reason: "y") else { Issue.record("phải từ chối"); return }
        #expect(reason.contains("chờ"))
        await arbiter.end()
        guard case .denied = await first else { Issue.record("yêu cầu đầu phải bị huỷ"); return }
    }

    @Test func controlledToolGatesTheHandler() async {
        struct Probe: ToolHandler { func call(arguments: JsonValue) async -> ToolResult { .ok("chạy") } }
        let arbiter = makeArbiter()
        let tool = ControlledTool(arbiter: arbiter, inner: Probe())
        #expect(await tool.call(arguments: [:]).isError)
        _ = await arbiter.request(agentName: "A", reason: "x")
        #expect(await tool.call(arguments: [:]).text == "chạy")
        await arbiter.pause(reason: "hotkey")
        let blocked = await tool.call(arguments: [:])
        #expect(blocked.isError && blocked.text.hasPrefix("control paused"))
    }
}
