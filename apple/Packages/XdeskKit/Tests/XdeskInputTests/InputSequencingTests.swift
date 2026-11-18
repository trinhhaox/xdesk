import Testing
import XdeskWire
@testable import XdeskInput

@Suite struct InputSequencingTests {
    private func down(_ x: Float = 0.5) -> InputEvent { .button(down: true, x: x, y: 0.5) }
    private func up() -> InputEvent { .button(down: false, x: 0.5, y: 0.5) }

    // MARK: Sequencer

    @Test func assignsSeqOnlyToReliableEvents() {
        var s = InputSequencer()
        let out = s.prepare([.move(x: 0.1, y: 0.1), down(), .scroll(dx: 1, dy: 1), up(), .key(usage: 4, down: true)], nowMs: 0)
        #expect(out.map(\.seq) == [0, 1, 0, 2, 3])
        #expect(s.pendingCount == 3)
    }

    @Test func ackClearsUpToSeq() {
        var s = InputSequencer()
        _ = s.prepare([down(), up(), down()], nowMs: 0)
        s.acknowledge(upTo: 2)
        #expect(s.pendingCount == 1)
        s.acknowledge(upTo: 3)
        #expect(s.pendingCount == 0)
        #expect(s.resendDue(nowMs: 10_000).resend.isEmpty)
    }

    @Test func resendsThreeTimesThenGivesUp() {
        var s = InputSequencer()
        _ = s.prepare([down()], nowMs: 0)
        #expect(s.resendDue(nowMs: 99).resend.isEmpty)
        for round in 1...3 {
            let due = s.resendDue(nowMs: Int64(round) * 100)
            #expect(due.resend.map(\.seq) == [1], "resend \(round)")
            #expect(due.abandoned.isEmpty)
        }
        let last = s.resendDue(nowMs: 400)
        #expect(last.resend.isEmpty)
        #expect(last.abandoned.map(\.seq) == [1])
        #expect(s.pendingCount == 0)
    }

    @Test func ackBetweenResendsStopsResending() {
        var s = InputSequencer()
        _ = s.prepare([down()], nowMs: 0)
        #expect(s.resendDue(nowMs: 100).resend.count == 1)
        s.acknowledge(upTo: 1)
        #expect(s.resendDue(nowMs: 200).resend.isEmpty)
    }

    @Test func tracksHeldInputForHeartbeat() {
        var s = InputSequencer()
        #expect(!s.hasHeldInput)
        _ = s.prepare([down()], nowMs: 0)
        #expect(s.hasHeldInput)
        _ = s.prepare([up(), .key(usage: 4, down: true)], nowMs: 1)
        #expect(s.hasHeldInput)
        _ = s.prepare([.key(usage: 4, down: false)], nowMs: 2)
        #expect(!s.hasHeldInput)
    }

    @Test func batchesAtMostMaxBatch() {
        let events = (0..<100).map { _ in InputEvent.move(x: 0, y: 0) }
        let batches = InputSequencer.batches(events)
        #expect(batches.map(\.count) == [42, 42, 16])
        #expect(InputEvent.maxBatch == 42)
        #expect(InputSequencer.batches([]).isEmpty)
    }

    // MARK: Receiver

    private func seqEvent(_ seq: UInt32) -> InputEvent {
        var e = down(); e.seq = seq; return e
    }

    @Test func receiverDeliversInOrderAndAcksContiguous() {
        var r = InputReceiver()
        #expect(r.accept([seqEvent(1), seqEvent(2)], nowMs: 0).map(\.seq) == [1, 2])
        #expect(r.ackSeq == 2)
        #expect(r.accept([seqEvent(2)], nowMs: 1).isEmpty) // trùng
        #expect(r.accept([seqEvent(4)], nowMs: 2).isEmpty) // chờ 3
        #expect(r.ackSeq == 2)
        #expect(r.accept([seqEvent(3)], nowMs: 3).map(\.seq) == [3, 4])
        #expect(r.ackSeq == 4)
    }

    @Test func receiverPassesUnreliableEventsImmediately() {
        var r = InputReceiver()
        let out = r.accept([.move(x: 0.1, y: 0.1), seqEvent(2)], nowMs: 0)
        #expect(out.map(\.kind) == [.move])
        #expect(r.ackSeq == 0)
    }

    @Test func receiverSkipsGapAfterTimeout() {
        var r = InputReceiver()
        _ = r.accept([seqEvent(2)], nowMs: 0)
        #expect(r.accept([.heartbeat], nowMs: 499).map(\.kind) == [.scroll])
        let out = r.accept([.heartbeat], nowMs: 500)
        #expect(out.map(\.seq) == [0, 2])
        #expect(r.ackSeq == 2)
    }

    // MARK: Rate limiter, chunker

    @Test func rateLimiterCapsAtThousandPerSecond() {
        var l = InputRateLimiter()
        #expect(l.take(1500, nowMs: 0) == 1000)
        #expect(l.take(100, nowMs: 0) == 0)
        #expect(l.take(1000, nowMs: 100) == 100)
        #expect(l.take(5000, nowMs: 10_000) == 1000)
    }

    @Test func chunkerKeepsCharactersWhole() {
        let text = "Tiếng Việt có dấu 👨‍👩‍👧 xong"
        let chunks = TextChunker.split(text, limit: 8) { $0.utf16.count }
        #expect(chunks.joined() == text)
        for chunk in chunks where chunk.count > 1 { #expect(chunk.utf16.count <= 8) }
        #expect(TextChunker.split("", limit: 8) { $0.utf16.count }.isEmpty)
        #expect(TextChunker.splitUtf8(String(repeating: "ế", count: 3000), maxBytes: 4096).allSatisfy { $0.utf8.count <= 4096 })
    }

    @Test func sanitizedClampsAndDropsNonFinite() {
        #expect(InputEvent.move(x: 1.5, y: -0.2).sanitized()?.x == 1)
        #expect(InputEvent.move(x: 1.5, y: -0.2).sanitized()?.y == 0)
        #expect(InputEvent.move(x: .nan, y: 0).sanitized() == nil)
        #expect(InputEvent.scroll(dx: 5000, dy: -5000).sanitized()?.dx == 5000)
    }
}
