import Testing
@testable import XdeskWire

@Suite struct NackTrackerTests {
    private func partial(_ frameNo: UInt32, length: Int, keep: [Int], into r: inout Reassembler, nowMs: Int) throws {
        let ps = try Packetizer(streamId: 1).packetize(frame: [UInt8](repeating: 1, count: length), frameNo: frameNo, ptsMs: 0)
        for i in keep { _ = try r.ingest(ps[i], nowMs: nowMs) }
    }

    @Test func nacksOnlyAfterDelayAndRespectsRetryInterval() throws {
        var r = Reassembler()
        var t = NackTracker()
        try partial(0, length: 1192 * 3, keep: [0, 2], into: &r, nowMs: 0)
        #expect(t.poll(&r, nowMs: 19).nacks.isEmpty)
        #expect(t.poll(&r, nowMs: 20).nacks == [NackEntry(frameNo: 0, fragIdx: 1)])
        #expect(t.poll(&r, nowMs: 30).nacks.isEmpty)
        #expect(t.poll(&r, nowMs: 60).nacks == [NackEntry(frameNo: 0, fragIdx: 1)])
    }

    @Test func wholeFrameGapIsNackedWithSentinel() throws {
        var r = Reassembler()
        var t = NackTracker()
        try partial(1, length: 10, keep: [0], into: &r, nowMs: 0)
        #expect(t.poll(&r, nowMs: 0).nacks.isEmpty)
        #expect(t.poll(&r, nowMs: 25).nacks == [NackEntry(frameNo: 0, fragIdx: NackEntry.wholeFrame)])
    }

    @Test func capsEntriesPerPacketAndContinuesNextPoll() throws {
        var r = Reassembler()
        var t = NackTracker()
        try partial(0, length: 1192 * 100, keep: [0], into: &r, nowMs: 0)
        let first = t.poll(&r, nowMs: 25).nacks
        #expect(first.count == NackEntry.maxEntries)
        let second = t.poll(&r, nowMs: 26).nacks
        #expect(second.count == 99 - NackEntry.maxEntries)
        #expect(Set(first).isDisjoint(with: second))
    }

    @Test func givesUpAndReportsAbandonedFrames() throws {
        var r = Reassembler()
        var t = NackTracker()
        try partial(1, length: 1192 * 2, keep: [0], into: &r, nowMs: 0)
        _ = t.poll(&r, nowMs: 0)
        let poll = t.poll(&r, nowMs: 600)
        #expect(poll.abandoned == [0, 1])
        #expect(poll.nacks.isEmpty)
        #expect(r.watermark == 2)
    }

    @Test func customConfigIsHonoured() throws {
        var config = NackTracker.Config()
        config.nackDelayMs = 0
        var t = NackTracker(config: config)
        var r = Reassembler()
        try partial(0, length: 1192 * 2, keep: [1], into: &r, nowMs: 0)
        #expect(t.poll(&r, nowMs: 0).nacks == [NackEntry(frameNo: 0, fragIdx: 0)])
    }
}
