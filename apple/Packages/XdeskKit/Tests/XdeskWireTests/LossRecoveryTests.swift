import Testing
@testable import XdeskWire

/// Mô phỏng xác định: gửi N frame qua kênh UDP mất `lossPercent`%, người nhận NACK qua kênh ngược cũng mất gói.
@Suite struct LossRecoveryTests {
    private struct Result {
        var delivered: [UInt32: [UInt8]] = [:]
        var nackPackets = 0
        var retransmitted = 0
        var abandoned = 0
    }

    private func simulate(seed: UInt64, frames: Int, lossPercent: Int) throws -> Result {
        var rng = SplitMix64(seed: seed)
        let sender = Packetizer(streamId: 1)
        var sent: [UInt32: [MediaPacket]] = [:]
        var reassembler = Reassembler()
        var config = NackTracker.Config()
        config.giveUpMs = 60_000
        var tracker = NackTracker(config: config)
        var result = Result()

        func lost(_ rng: inout SplitMix64) -> Bool { Int.random(in: 0..<100, using: &rng) < lossPercent }
        func deliver(_ packet: MediaPacket, nowMs: Int, _ result: inout Result, _ r: inout Reassembler) throws {
            // Đi qua đường dây thật: mã hoá rồi giải mã.
            let wire = try packet.encode()
            if let f = try r.ingest(try MediaPacket.decode(wire), nowMs: nowMs) { result.delivered[f.frameNo] = f.data }
        }

        var nextFrame: UInt32 = 0
        var now = 0
        while result.delivered.count < frames, now < 120_000 {
            if Int(nextFrame) < frames, now >= Int(nextFrame) * 33 {
                let data = ReassemblerTests.frameData(nextFrame, length: Int.random(in: 1...12_000, using: &rng))
                let packets = try sender.packetize(frame: data, frameNo: nextFrame, ptsMs: UInt32(now), isKeyframe: nextFrame == 0)
                sent[nextFrame] = packets
                // Frame cuối không bị mất: trong luồng thật, frame kế tiếp lộ ra khoảng trống.
                let isLast = Int(nextFrame) == frames - 1
                for p in packets where isLast || !lost(&rng) { try deliver(p, nowMs: now, &result, &reassembler) }
                nextFrame += 1
            }
            let poll = tracker.poll(&reassembler, nowMs: now)
            result.abandoned += poll.abandoned.count
            if !poll.nacks.isEmpty {
                result.nackPackets += 1
                let wire = try MediaPacket.nack(streamId: 1, entries: poll.nacks).encode()
                if !lost(&rng) {
                    for entry in try NackPayload.decode(try MediaPacket.decode(wire).payload) {
                        let all = sent[entry.frameNo] ?? []
                        let wanted = entry.fragIdx == NackEntry.wholeFrame ? all : all.filter { $0.header.fragIdx == entry.fragIdx }
                        for p in wanted where !lost(&rng) {
                            result.retransmitted += 1
                            try deliver(p, nowMs: now, &result, &reassembler)
                        }
                    }
                }
            }
            now += 10
        }
        return result
    }

    @Test(arguments: [1 as UInt64, 2, 3, 20_261_118])
    func recoversEveryFrameAt5PercentLossWithNack(seed: UInt64) throws {
        let frames = 300
        let result = try simulate(seed: seed, frames: frames, lossPercent: 5)
        #expect(result.delivered.count == frames)
        #expect(result.abandoned == 0)
        #expect(result.nackPackets > 0 && result.retransmitted > 0)
        for n in 0..<frames {
            let data = try #require(result.delivered[UInt32(n)])
            #expect(data == ReassemblerTests.frameData(UInt32(n), length: data.count))
        }
    }

    @Test func noLossNeedsNoNack() throws {
        let result = try simulate(seed: 5, frames: 60, lossPercent: 0)
        #expect(result.delivered.count == 60)
        #expect(result.nackPackets == 0)
    }
}
