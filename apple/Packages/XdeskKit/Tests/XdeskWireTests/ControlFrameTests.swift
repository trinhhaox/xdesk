import Testing
@testable import XdeskWire

@Suite struct ControlFrameTests {
    @Test func roundTripAllKinds() throws {
        for kind in ControlFrameKind.allCases {
            let frame = ControlFrame(kind: kind, payload: [1, 2, 3, 4, 5])
            let bytes = try ControlFrameCodec.encode(frame)
            let decoded = try #require(try ControlFrameCodec.decode(bytes))
            #expect(decoded.frame == frame)
            #expect(decoded.consumed == bytes.count)
        }
    }

    @Test func literalHexLayout() throws {
        let bytes = try ControlFrameCodec.encode(ControlFrame(kind: .handshake, payload: [0xAA, 0xBB, 0xCC]))
        #expect(WireHex.encode(bytes) == "0000000401aabbcc")
    }

    @Test func consumesOnlyFirstFrame() throws {
        let one = try ControlFrameCodec.encode(ControlFrame(kind: .control, payload: [9]))
        let decoded = try #require(try ControlFrameCodec.decode(one + [0xDE, 0xAD]))
        #expect(decoded.consumed == one.count)
    }

    @Test func maxLengthBoundary() throws {
        let max = ControlFrame(kind: .control, payload: [UInt8](repeating: 7, count: ControlFrame.maxLength - 1))
        let bytes = try ControlFrameCodec.encode(max)
        #expect(try ControlFrameCodec.decode(bytes)?.consumed == ControlFrame.maxLength + 4)
        let over = ControlFrame(kind: .control, payload: [UInt8](repeating: 7, count: ControlFrame.maxLength))
        expectWireError("frameTooLarge") { _ = try ControlFrameCodec.encode(over) }
    }

    @Test func bulkChunkLimit() throws {
        let ok = ControlFrame(kind: .bulk, payload: [UInt8](repeating: 1, count: ControlFrame.maxBulkPayload))
        #expect(try ControlFrameCodec.decode(try ControlFrameCodec.encode(ok)) != nil)
        let big = ControlFrame(kind: .bulk, payload: [UInt8](repeating: 1, count: ControlFrame.maxBulkPayload + 1))
        expectWireError("payloadTooLarge") { _ = try ControlFrameCodec.encode(big) }
        var raw = try ControlFrameCodec.encode(ControlFrame(kind: .control, payload: big.payload))
        raw[4] = ControlFrameKind.bulk.rawValue
        expectWireError("payloadTooLarge") { _ = try ControlFrameCodec.decode(raw) }
    }

    @Test func incompleteReturnsNil() throws {
        let bytes = try ControlFrameCodec.encode(ControlFrame(kind: .control, payload: [1, 2, 3]))
        for n in 0..<bytes.count { #expect(try ControlFrameCodec.decode(Array(bytes.prefix(n))) == nil) }
    }

    @Test func lengthIsRejectedEvenBeforeKindArrives() {
        expectWireError("frameTooLarge") { _ = try ControlFrameCodec.decode([0xFF, 0xFF, 0xFF, 0xFF]) }
        expectWireError("invalidFrameLength") { _ = try ControlFrameCodec.decode([0, 0, 0, 0]) }
    }

    @Test func streamDecoderHandlesSplitAndCoalescedReads() throws {
        let a = try ControlFrameCodec.encode(ControlFrame(kind: .control, payload: [1]))
        let b = try ControlFrameCodec.encode(ControlFrame(kind: .bulk, payload: [2, 3]))
        var decoder = ControlFrameDecoder()
        decoder.append(Array((a + b).prefix(3)))
        #expect(try decoder.next() == nil)
        decoder.append(Array((a + b).dropFirst(3)))
        #expect(try decoder.next()?.payload == [1])
        #expect(try decoder.next()?.payload == [2, 3])
        #expect(try decoder.next() == nil)
        #expect(decoder.bufferedCount == 0)
    }

    @Test func vectors() throws {
        let v = try Vectors.load("control-frames.json")
        for c in try v.list("frames") {
            let kind = try #require(ControlFrameKind(rawValue: UInt8(try c.int("kind"))))
            let frame = ControlFrame(kind: kind, payload: try c.bytes("payloadHex"))
            #expect(try ControlFrameCodec.encode(frame) == (try c.bytes("hex")), label(c))
            #expect(try ControlFrameCodec.decode(try c.bytes("hex"))?.frame == frame)
        }
        for c in try v.list("invalidFrames") {
            let bytes = try c.bytes("hex")
            expectWireError(try c.str("error")) { _ = try ControlFrameCodec.decode(bytes) }
        }
        for c in try v.list("incompleteFrames") { #expect(try ControlFrameCodec.decode(try c.bytes("hex")) == nil) }
    }
}
