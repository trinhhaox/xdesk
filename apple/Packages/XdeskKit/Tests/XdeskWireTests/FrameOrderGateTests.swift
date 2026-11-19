import Testing
@testable import XdeskWire

@Suite struct FrameOrderGateTests {
    private func frame(_ n: UInt32, key: Bool = false) -> AssembledFrame {
        AssembledFrame(streamId: 1, frameNo: n, ptsMs: n &* 16, isKeyframe: key, data: [UInt8(truncatingIfNeeded: n)])
    }

    @Test func inOrderFramesReleaseImmediatelyWithoutHold() {
        var gate = FrameOrderGate()
        for n in UInt32(0)..<5 {
            let out = gate.push(frame(n, key: n == 0), nowMs: Int(n))
            #expect(out.frames.map(\.frameNo) == [n] && out.skipTo == nil && !out.keyframeNeeded)
        }
        #expect(!gate.isHolding)
    }

    @Test func idrCompletingAfterPFramesReleasesInOrder() {
        var gate = FrameOrderGate()
        #expect(gate.push(frame(1), nowMs: 0).frames.isEmpty)
        #expect(gate.push(frame(2), nowMs: 5).frames.isEmpty)
        let out = gate.push(frame(0, key: true), nowMs: 30)
        #expect(out.frames.map(\.frameNo) == [0, 1, 2] && !out.keyframeNeeded && out.skipTo == nil)
        #expect(!gate.isHolding)
    }

    @Test func missingPFrameTimesOutThenSkipsAndRequestsKeyframe() {
        var gate = FrameOrderGate()
        _ = gate.push(frame(0, key: true), nowMs: 0)
        #expect(gate.push(frame(2), nowMs: 10).frames.isEmpty)
        #expect(gate.push(frame(3), nowMs: 12).frames.isEmpty)
        #expect(gate.poll(nowMs: 10 + FrameOrderGate.holdBoundMs - 1, pendingKeyframes: []).frames.isEmpty)
        let out = gate.poll(nowMs: 10 + FrameOrderGate.holdBoundMs, pendingKeyframes: [])
        #expect(out.frames.map(\.frameNo) == [2, 3] && out.skipTo == 2 && out.keyframeNeeded)
        #expect(gate.push(frame(1), nowMs: 80).frames.isEmpty)
        #expect(gate.push(frame(4), nowMs: 81).frames.map(\.frameNo) == [4])
    }

    @Test func missingIdrWaitsForNextKeyframe() {
        var gate = FrameOrderGate()
        _ = gate.push(frame(1), nowMs: 0)
        _ = gate.push(frame(2), nowMs: 1)
        let out = gate.poll(nowMs: 100, pendingKeyframes: [0])
        #expect(out.frames.isEmpty && out.keyframeNeeded && out.skipTo == 1)
        let later = gate.push(frame(3), nowMs: 110)
        #expect(later.frames.isEmpty && later.keyframeNeeded)
        let idr = gate.push(frame(10, key: true), nowMs: 200)
        #expect(idr.frames.map(\.frameNo) == [10] && idr.skipTo == 10)
        #expect(gate.push(frame(11), nowMs: 201).frames.map(\.frameNo) == [11])
    }

    @Test func completedKeyframeJumpsOverMissingFrames() {
        var gate = FrameOrderGate()
        _ = gate.push(frame(0, key: true), nowMs: 0)
        _ = gate.push(frame(2), nowMs: 1)
        let out = gate.push(frame(5, key: true), nowMs: 2)
        #expect(out.frames.map(\.frameNo) == [5] && out.skipTo == 5 && !out.keyframeNeeded)
        #expect(!gate.isHolding)
    }

    @Test func duplicatesAndStaleFramesAreIgnored() {
        var gate = FrameOrderGate()
        #expect(gate.push(frame(0, key: true), nowMs: 0).frames.count == 1)
        #expect(gate.push(frame(0, key: true), nowMs: 1).frames.isEmpty)
        _ = gate.push(frame(2), nowMs: 2)
        #expect(gate.push(frame(2), nowMs: 3).frames.isEmpty)
        #expect(gate.push(frame(1), nowMs: 4).frames.map(\.frameNo) == [1, 2])
        #expect(gate.push(frame(1), nowMs: 5).frames.isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func hugeFrameJumpStaysCheap() {
        var gate = FrameOrderGate()
        _ = gate.push(frame(0, key: true), nowMs: 0)
        let far = UInt32.max - 10
        #expect(gate.push(frame(far), nowMs: 1).frames.isEmpty)
        let out = gate.poll(nowMs: 1 + FrameOrderGate.holdBoundMs, pendingKeyframes: [])
        #expect(out.frames.map(\.frameNo) == [far] && out.skipTo == far)
        let keyJump = gate.push(frame(UInt32.max - 5, key: true), nowMs: 100)
        #expect(keyJump.frames.map(\.frameNo) == [UInt32.max - 5])
    }
}
