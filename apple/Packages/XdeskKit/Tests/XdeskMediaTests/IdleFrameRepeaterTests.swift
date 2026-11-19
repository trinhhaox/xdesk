import Foundation
import Testing
@testable import XdeskMedia

final class FireCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func hit() { lock.withLock { n += 1 } }
    var count: Int { lock.withLock { n } }
}

@Suite struct IdleFrameRepeaterTests {
    @Test func firesOnceAfterIdle() async throws {
        let counter = FireCounter()
        let repeater = IdleFrameRepeater(delay: .milliseconds(30)) { counter.hit() }
        repeater.frameEncoded()
        try await Task.sleep(for: .milliseconds(200))
        #expect(counter.count == 1)
    }

    @Test func steadyFramesNeverFire() async throws {
        let counter = FireCounter()
        let repeater = IdleFrameRepeater(delay: .milliseconds(80)) { counter.hit() }
        for _ in 0..<10 {
            repeater.frameEncoded()
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(counter.count == 0)
        try await Task.sleep(for: .milliseconds(250))
        #expect(counter.count == 1)
    }

    @Test func cancelStopsPendingRepeat() async throws {
        let counter = FireCounter()
        let repeater = IdleFrameRepeater(delay: .milliseconds(30)) { counter.hit() }
        repeater.frameEncoded()
        repeater.cancel()
        try await Task.sleep(for: .milliseconds(150))
        #expect(counter.count == 0)
    }
}
