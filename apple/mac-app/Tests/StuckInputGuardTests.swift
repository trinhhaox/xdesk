import CoreGraphics
import Testing
@testable import Xdesk

@Suite struct StuckInputGuardTests {
    private let p = CGPoint(x: 10, y: 20)

    @Test func releaseAllLiftsHeldButtonsAndKeys() {
        let fake = FakeEventInjector()
        let guardian = StuckInputGuard(injector: fake)
        guardian.buttonDown(.left, at: p)
        guardian.keyDown(0)
        guardian.keyDown(55)
        guardian.releaseAll()
        #expect(fake.calls == [
            .button(.left, down: false, p, clicks: 1),
            .key(55, down: false, flags: []), .key(0, down: false, flags: []),
        ])
        #expect(!guardian.isHolding)
        guardian.releaseAll()
        #expect(fake.calls.count == 3)
    }

    @Test func idleHoldIsReleasedAfterOneSecond() {
        let fake = FakeEventInjector()
        let guardian = StuckInputGuard(injector: fake)
        guardian.noteActivity(nowMs: 0)
        guardian.buttonDown(.left, at: p)
        #expect(!guardian.tick(nowMs: 1000))
        #expect(fake.calls.isEmpty)
        #expect(guardian.tick(nowMs: 1001))
        #expect(fake.calls == [.button(.left, down: false, p, clicks: 1)])
    }

    @Test func heartbeatActivityKeepsHoldAlive() {
        let fake = FakeEventInjector()
        let guardian = StuckInputGuard(injector: fake)
        guardian.buttonDown(.left, at: p)
        for t in stride(from: 250, through: 5000, by: 250) {
            guardian.noteActivity(nowMs: Int64(t))
            #expect(!guardian.tick(nowMs: Int64(t)))
        }
        #expect(fake.calls.isEmpty)
    }

    @Test func tickDoesNothingWhenNothingHeld() {
        let guardian = StuckInputGuard(injector: FakeEventInjector())
        #expect(!guardian.tick(nowMs: 100_000))
    }

    @Test func releasedButtonIsNotReleasedAgain() {
        let fake = FakeEventInjector()
        let guardian = StuckInputGuard(injector: fake)
        guardian.buttonDown(.left, at: p)
        #expect(guardian.buttonUp(.left, at: p))
        #expect(!guardian.buttonUp(.left, at: p))
        guardian.releaseAll()
        #expect(fake.calls.isEmpty)
    }

    @Test func releaseUsesLastKnownPoint() {
        let fake = FakeEventInjector()
        let guardian = StuckInputGuard(injector: fake)
        guardian.buttonDown(.right, at: p)
        guardian.moved(to: CGPoint(x: 99, y: 88))
        guardian.releaseAll()
        #expect(fake.calls == [.button(.right, down: false, CGPoint(x: 99, y: 88), clicks: 1)])
    }
}
