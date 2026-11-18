import Testing
@testable import XdeskWire

@Suite struct InputEventTests {
    @Test func literalLayout() throws {
        let event = InputEvent(kind: .down, button: 1, mods: 8, seq: 2, x: 0.25, y: 0.75)
        let bytes = try InputEvent.encodeBatch([event])
        #expect(bytes.count == InputEvent.size)
        #expect(WireHex.encode(bytes) == "0101" + "0008" + "00000002" + "3e800000" + "3f400000" + "00000000" + "00000000" + "0000" + "0000")
    }

    @Test func randomBatchRoundTrip() throws {
        var rng = SplitMix64(seed: 7)
        for _ in 0..<200 {
            let count = Int.random(in: 1...InputEvent.maxBatch, using: &rng)
            let events = (0..<count).map { _ in
                InputEvent(
                    kind: InputKind.allCases.randomElement(using: &rng) ?? .move, button: .random(in: 0...255, using: &rng),
                    mods: .random(in: 0...UInt16.max, using: &rng), seq: .random(in: 0...UInt32.max, using: &rng),
                    x: .random(in: 0...1, using: &rng), y: .random(in: 0...1, using: &rng),
                    dx: .random(in: -100...100, using: &rng), dy: .random(in: -100...100, using: &rng),
                    keyUsage: .random(in: 0...UInt16.max, using: &rng)
                )
            }
            #expect(try InputEvent.decodeBatch(try InputEvent.encodeBatch(events)) == events)
        }
    }

    @Test func scrollAllowsAnyFiniteDelta() throws {
        let e = InputEvent(kind: .scroll, seq: 1, x: 5, y: -2, dx: 1e6, dy: -1e6)
        #expect(try InputEvent.decodeBatch(try InputEvent.encodeBatch([e])) == [e])
    }

    @Test func encodeRejectsInvalid() {
        expectWireError("invalidInput") { _ = try InputEvent.encodeBatch([]) }
        let tooMany = [InputEvent](repeating: InputEvent(kind: .key, seq: 0), count: InputEvent.maxBatch + 1)
        expectWireError("invalidInput") { _ = try InputEvent.encodeBatch(tooMany) }
        expectWireError("invalidInput") { _ = try InputEvent.encodeBatch([InputEvent(kind: .move, seq: 0, x: .nan)]) }
        expectWireError("invalidInput") { _ = try InputEvent.encodeBatch([InputEvent(kind: .touch, seq: 0, x: 1.5)]) }
    }

    @Test func nonZeroPadIsIgnored() throws {
        var bytes = try InputEvent.encodeBatch([InputEvent(kind: .key, seq: 1, keyUsage: 4)])
        bytes[26] = 0xAB
        #expect(try InputEvent.decodeBatch(bytes).first?.keyUsage == 4)
    }

    @Test func ackRoundTripAndBounds() throws {
        #expect(try InputAck.decode(InputAck(seq: 258).encode()) == InputAck(seq: 258))
        expectWireError("invalidInput") { _ = try InputAck.decode([1, 2, 3]) }
    }

    @Test func vectors() throws {
        let v = try Vectors.load("input-events.json")
        #expect(try v.int("eventSize") == InputEvent.size)
        for c in try v.list("events") {
            let event = InputEvent(
                kind: try #require(InputKind(rawValue: UInt8(try c.int("kind")))), button: UInt8(try c.int("button")),
                mods: UInt16(try c.int("mods")), seq: UInt32(try c.int("seq")), x: try c.float("x"), y: try c.float("y"),
                dx: try c.float("dx"), dy: try c.float("dy"), keyUsage: UInt16(try c.int("keyUsage"))
            )
            #expect(try InputEvent.encodeBatch([event]) == (try c.bytes("hex")), label(c))
            #expect(try InputEvent.decodeBatch(try c.bytes("hex")) == [event])
        }
        for c in try v.list("batches") {
            #expect(try InputEvent.decodeBatch(try c.bytes("payloadHex")).count == (try c.int("count")))
        }
        for c in try v.list("acks") {
            #expect(try InputAck.decode(try c.bytes("hex")).seq == UInt32(try c.int("seq")))
        }
        for c in try v.list("invalid") {
            let bytes = try c.bytes("payloadHex")
            expectWireError(try c.str("error")) { _ = try InputEvent.decodeBatch(bytes) }
        }
    }
}
