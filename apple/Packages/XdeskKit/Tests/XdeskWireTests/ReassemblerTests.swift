import Testing
@testable import XdeskWire

@Suite struct ReassemblerTests {
    static func frameData(_ frameNo: UInt32, length: Int) -> [UInt8] { (0..<length).map { UInt8(truncatingIfNeeded: Int(frameNo) &* 31 &+ $0) } }

    private func packets(_ frameNo: UInt32, length: Int, key: Bool = false) throws -> [MediaPacket] {
        try Packetizer(streamId: 1).packetize(frame: Self.frameData(frameNo, length: length), frameNo: frameNo, ptsMs: frameNo &* 33, isKeyframe: key)
    }

    @Test func inOrderDelivery() throws {
        var r = Reassembler()
        var out: [AssembledFrame] = []
        for n in UInt32(0)..<5 {
            for p in try packets(n, length: 3000, key: n == 0) { if let f = try r.ingest(p, nowMs: 0) { out.append(f) } }
        }
        #expect(out.map(\.frameNo) == [0, 1, 2, 3, 4])
        #expect(out[0].isKeyframe && !out[1].isKeyframe)
        #expect(out[2].ptsMs == 66)
        #expect(out.allSatisfy { $0.data == Self.frameData($0.frameNo, length: 3000) })
        #expect(r.watermark == 5 && r.gaps.isEmpty && r.pending.isEmpty)
    }

    @Test func shuffledAndDuplicatedPacketsDeliverEachFrameOnce() throws {
        var rng = SplitMix64(seed: 99)
        var all: [MediaPacket] = []
        for n in UInt32(0)..<30 { all += try packets(n, length: Int.random(in: 1...9000, using: &rng)) }
        all += all.shuffled(using: &rng).prefix(all.count / 2)
        all.shuffle(using: &rng)
        var r = Reassembler()
        var delivered: [UInt32: [UInt8]] = [:]
        for p in all {
            if let f = try r.ingest(p, nowMs: 0) {
                #expect(delivered[f.frameNo] == nil)
                delivered[f.frameNo] = f.data
            }
        }
        #expect(delivered.count == 30)
        for (n, data) in delivered { #expect(data == Self.frameData(n, length: data.count)) }
    }

    @Test func lateDuplicateOfFinishedFrameIsIgnored() throws {
        var r = Reassembler()
        let ps = try packets(0, length: 2500)
        for p in ps { _ = try r.ingest(p, nowMs: 0) }
        #expect(try r.ingest(ps[0], nowMs: 1) == nil)
        #expect(r.pending.isEmpty)
    }

    @Test func invalidFragmentIsRejected() throws {
        var r = Reassembler()
        var p = try #require(try packets(0, length: 10).first)
        p.header.fragIdx = 1
        expectWireError("invalidFragment") { _ = try r.ingest(p, nowMs: 0) }
        p.header.fragIdx = 0
        p.header.fragCnt = 2049
        expectWireError("fragmentCountTooLarge") { _ = try r.ingest(p, nowMs: 0) }
        p.header.fragCnt = 1
        p.payload = []
        expectWireError("emptyPayload") { _ = try r.ingest(p, nowMs: 0) }
        p.payload = [UInt8](repeating: 0, count: 1201)
        expectWireError("payloadTooLarge") { _ = try r.ingest(p, nowMs: 0) }
        p.payload = [1]
        p.header.type = .input
        expectWireError("unexpectedPacketType") { _ = try r.ingest(p, nowMs: 0) }
    }

    @Test func inconsistentFragmentCountIsRejected() throws {
        var r = Reassembler()
        let ps = try packets(0, length: 3000)
        _ = try r.ingest(ps[0], nowMs: 0)
        var liar = ps[1]
        liar.header.fragCnt = 4
        expectWireError("inconsistentFragmentCount") { _ = try r.ingest(liar, nowMs: 0) }
    }

    @Test func gapsPendingAndAbandon() throws {
        var r = Reassembler()
        let f2 = try packets(2, length: 3000)
        _ = try r.ingest(f2[0], nowMs: 10)
        #expect(r.gaps == [0, 1])
        #expect(r.pending == [PendingFrame(frameNo: 2, missing: [1, 2], firstSeenMs: 10)])
        r.abandon(0)
        r.abandon(1)
        #expect(r.watermark == 2 && r.abandonedCount == 2)
        r.abandon(2)
        #expect(r.watermark == 3 && r.pending.isEmpty)
        #expect(try r.ingest(f2[1], nowMs: 20) == nil)
    }

    @Test func windowOverflowDropsOldestFrames() throws {
        var r = Reassembler()
        _ = try r.ingest(try #require(try packets(0, length: 3000).first), nowMs: 0)
        _ = try r.ingest(try #require(try packets(Reassembler.window, length: 100).first), nowMs: 0)
        #expect(r.watermark == 1 && r.abandonedCount == 1 && r.pending.isEmpty)
    }

    /// Một gói có frameNo rất lớn không được làm treo: watermark nhảy một lần.
    @Test(.timeLimit(.minutes(1))) func hugeFrameJumpDoesNotHang() throws {
        var r = Reassembler()
        _ = try r.ingest(try #require(try packets(0, length: 3000).first), nowMs: 0)
        let far = UInt32.max - 10
        _ = try r.ingest(try #require(try packets(far, length: 3000).first), nowMs: 1)
        #expect(r.watermark == far - Reassembler.window + 1)
        #expect(r.pending.map(\.frameNo) == [far])
    }

    @Test func pendingByteCapEvictsOldest() throws {
        var r = Reassembler(maxPendingBytes: 2000)
        for n in UInt32(0)..<3 { _ = try r.ingest(try #require(try packets(n, length: 3000).first), nowMs: 0) }
        #expect(r.pending.map(\.frameNo) == [2])
        #expect(r.abandonedCount == 2)
    }

    @Test func firstFrameNoSetsInitialWatermark() throws {
        var r = Reassembler(firstFrameNo: 100)
        #expect(try r.ingest(try #require(try packets(5, length: 1).first), nowMs: 0) == nil)
        #expect(try r.ingest(try #require(try packets(100, length: 1).first), nowMs: 0)?.frameNo == 100)
    }

    @Test func packetizerLimits() throws {
        #expect(Packetizer(streamId: 1, maxPayload: 0).maxPayload == 1)
        #expect(Packetizer(streamId: 1, maxPayload: 99999).maxPayload == 1192)
        expectWireError("emptyPayload") { _ = try Packetizer(streamId: 1).packetize(frame: [], frameNo: 0, ptsMs: 0) }
        expectWireError("unexpectedPacketType") { _ = try Packetizer(streamId: 1).packetize(frame: [1], frameNo: 0, ptsMs: 0, type: .nack) }
        let huge = [UInt8](repeating: 0, count: 2048 * 1192 + 1)
        expectWireError("fragmentCountTooLarge") { _ = try Packetizer(streamId: 1).packetize(frame: huge, frameNo: 0, ptsMs: 0) }
        let max = [UInt8](repeating: 0, count: 2048 * 1192)
        #expect(try Packetizer(streamId: 1).packetize(frame: max, frameNo: 0, ptsMs: 0).count == 2048)
    }
}
