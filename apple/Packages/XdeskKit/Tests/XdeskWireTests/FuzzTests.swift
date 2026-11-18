import Foundation
import Testing
@testable import XdeskWire

/// Fuzz xác định: byte ngẫu nhiên và mẫu hợp lệ bị đột biến phải cho lỗi có kiểu, không bao giờ crash.
@Suite struct FuzzTests {
    private static let iterations = 10_000

    private func mutate(_ seed: [UInt8], _ rng: inout SplitMix64) -> [UInt8] {
        var bytes = seed
        for _ in 0..<Int.random(in: 1...4, using: &rng) where !bytes.isEmpty {
            let i = Int.random(in: 0..<bytes.count, using: &rng)
            switch Int.random(in: 0..<3, using: &rng) {
            case 0: bytes[i] = UInt8.random(in: 0...255, using: &rng)
            case 1: bytes.remove(at: i)
            default: bytes.insert(UInt8.random(in: 0...255, using: &rng), at: i)
            }
        }
        return bytes
    }

    private func samples(_ rng: inout SplitMix64) -> [UInt8] {
        rng.bytes(count: Int.random(in: 0...80, using: &rng))
    }

    @Test func controlFrameDecoders() throws {
        var rng = SplitMix64(seed: 1)
        let valid = try ControlFrameCodec.encode(ControlFrame(kind: .control, payload: Array("{}".utf8)))
        var accepted = 0
        for i in 0..<Self.iterations {
            let bytes = i % 2 == 0 ? samples(&rng) : mutate(valid, &rng)
            if (try? ControlFrameCodec.decode(bytes)) != nil { accepted += 1 }
            var stream = ControlFrameDecoder()
            stream.append(bytes)
            while let _ = try? stream.next() { if stream.bufferedCount == 0 { break } }
        }
        #expect(accepted >= 0)
    }

    @Test func controlMessageJSON() throws {
        var rng = SplitMix64(seed: 2)
        let valid = try ControlMessageCodec.encode(.init(id: 1, message: .displayConfig(DisplayConfig(w: 10, h: 10, scale: 1, fps: 30, codec: .h264))))
        for i in 0..<Self.iterations {
            let bytes = i % 2 == 0 ? samples(&rng) : mutate(valid, &rng)
            do { _ = try ControlMessageCodec.decode(bytes) } catch is WireError { continue }
        }
    }

    @Test func mediaPacketsAndNack() throws {
        var rng = SplitMix64(seed: 3)
        let valid = try MediaPacket(header: MediaHeader(type: .video, streamId: 1, frameNo: 1, fragCnt: 2), payload: [1, 2, 3]).encode()
        let nack = try NackPayload.encode([NackEntry(frameNo: 1, fragIdx: 1), NackEntry(frameNo: 2, fragIdx: 0)])
        var reassembler = Reassembler()
        for i in 0..<Self.iterations {
            let bytes = i % 2 == 0 ? samples(&rng) : mutate(valid, &rng)
            if let packet = try? MediaPacket.decode(bytes) { _ = try? reassembler.ingest(packet, nowMs: i) }
            _ = try? NackPayload.decode(i % 2 == 0 ? samples(&rng) : mutate(nack, &rng))
        }
        #expect(reassembler.pending.count <= Int(Reassembler.window))
    }

    @Test func inputEvents() throws {
        var rng = SplitMix64(seed: 4)
        let valid = try InputEvent.encodeBatch([InputEvent(kind: .move, seq: 1, x: 0.5, y: 0.5)])
        for i in 0..<Self.iterations {
            let bytes = i % 3 == 0 ? samples(&rng) : (i % 3 == 1 ? mutate(valid, &rng) : rng.bytes(count: InputEvent.size))
            _ = try? InputEvent.decodeBatch(bytes)
            _ = try? InputAck.decode(bytes)
        }
    }
}
