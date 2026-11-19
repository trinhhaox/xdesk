import Testing
@testable import XdeskMedia
import XdeskWire

private func chunk(frames: Int = 240, value: Int16 = 1) -> [Int16] { [Int16](repeating: value, count: frames * 2) }

@Suite struct AudioJitterBufferTests {
    @Test func waitsForTargetDepthBeforePlaying() {
        var jitter = AudioJitterBuffer()
        for seq in 0..<7 { jitter.push(sequence: UInt32(seq), pcm: chunk()) }
        #expect(jitter.depthMs == 35)
        #expect(jitter.pull(frames: 240).allSatisfy { $0 == 0 })
        jitter.push(sequence: 7, pcm: chunk())
        #expect(jitter.depthMs == 40)
        #expect(jitter.pull(frames: 240).allSatisfy { $0 == 1 })
        #expect(jitter.depthMs == 35)
    }

    @Test func underrunPlaysSilenceThenRebuffers() {
        var jitter = AudioJitterBuffer()
        for seq in 0..<8 { jitter.push(sequence: UInt32(seq), pcm: chunk()) }
        _ = jitter.pull(frames: 1920)
        let out = jitter.pull(frames: 480)
        #expect(out.allSatisfy { $0 == 0 })
        #expect(jitter.counters.underruns == 1)
        jitter.push(sequence: 8, pcm: chunk())
        #expect(jitter.pull(frames: 240).allSatisfy { $0 == 0 }, "phải đệm lại đủ 40 ms mới phát")
    }

    @Test func lateAndDuplicatePacketsAreDropped() {
        var jitter = AudioJitterBuffer()
        jitter.push(sequence: 5, pcm: chunk())
        jitter.push(sequence: 5, pcm: chunk())
        jitter.push(sequence: 3, pcm: chunk())
        #expect(jitter.counters.lateOrDuplicate == 2)
        #expect(jitter.bufferedFrames == 240)
    }

    @Test func gapIsConcealedWithSilence() {
        var jitter = AudioJitterBuffer()
        jitter.push(sequence: 0, pcm: chunk(value: 9))
        jitter.push(sequence: 3, pcm: chunk(value: 9))
        #expect(jitter.counters.concealedFrames == 480)
        #expect(jitter.bufferedFrames == 240 * 4)
    }

    @Test func hugeGapResetsStream() {
        var jitter = AudioJitterBuffer()
        jitter.push(sequence: 0, pcm: chunk())
        jitter.push(sequence: 500, pcm: chunk())
        #expect(jitter.counters.resets == 1)
        #expect(jitter.bufferedFrames == 240)
    }

    @Test func overflowTrimsToTarget() {
        var jitter = AudioJitterBuffer()
        for seq in 0..<25 { jitter.push(sequence: UInt32(seq), pcm: chunk()) }
        #expect(jitter.counters.overflowTrims >= 1)
        #expect(jitter.depthMs <= AudioJitterBuffer.overflowMs)
    }

    @Test func sequenceWrapAroundIsNotLate() {
        var jitter = AudioJitterBuffer()
        jitter.push(sequence: UInt32.max, pcm: chunk())
        jitter.push(sequence: 0, pcm: chunk())
        #expect(jitter.counters.lateOrDuplicate == 0 && jitter.counters.concealedFrames == 0)
    }

    @Test func rejectsOddSampleCount() {
        var jitter = AudioJitterBuffer()
        jitter.push(sequence: 0, pcm: [1, 2, 3])
        #expect(jitter.bufferedFrames == 0)
    }
}
