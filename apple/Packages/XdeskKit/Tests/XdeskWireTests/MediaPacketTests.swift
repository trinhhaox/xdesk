import Testing
@testable import XdeskWire

@Suite struct MediaPacketTests {
    @Test func literalHeaderLayout() throws {
        let header = MediaHeader(type: .video, streamId: 1, frameNo: 7, fragIdx: 0, fragCnt: 3, isKeyframe: true, ptsMs: 1000)
        let bytes = try MediaPacket(header: header, payload: [1, 2, 3]).encode()
        #expect(WireHex.encode(bytes) == "011000010000000700008003000003e8010203")
        #expect(bytes.count == MediaHeader.size + 3)
    }

    @Test func randomHeadersRoundTrip() throws {
        var rng = SplitMix64(seed: 42)
        for _ in 0..<500 {
            let cnt = UInt16.random(in: 1...MediaHeader.maxFragmentCount, using: &rng)
            let header = MediaHeader(
                type: MediaPacketType.allCases.randomElement(using: &rng) ?? .video, streamId: .random(in: 0...65535, using: &rng),
                frameNo: .random(in: 0...UInt32.max, using: &rng), fragIdx: .random(in: 0..<cnt, using: &rng), fragCnt: cnt,
                isKeyframe: Bool.random(using: &rng), ptsMs: .random(in: 0...UInt32.max, using: &rng)
            )
            let packet = MediaPacket(header: header, payload: rng.bytes(count: Int.random(in: 0...MediaPacket.maxPayload, using: &rng)))
            #expect(try MediaPacket.decode(try packet.encode()) == packet)
        }
    }

    @Test func encodeRejectsBadFragmentsAndPayload() {
        let bad: [(UInt16, UInt16, String)] = [(0, 0, "invalidFragment"), (5, 5, "invalidFragment"), (0, 2049, "fragmentCountTooLarge")]
        for (idx, cnt, code) in bad {
            let packet = MediaPacket(header: MediaHeader(type: .video, streamId: 0, frameNo: 0, fragIdx: idx, fragCnt: cnt), payload: [])
            expectWireError(code) { _ = try packet.encode() }
        }
        let big = MediaPacket(header: MediaHeader(type: .video, streamId: 0, frameNo: 0), payload: [UInt8](repeating: 0, count: 1201))
        expectWireError("payloadTooLarge") { _ = try big.encode() }
    }

    @Test func vectors() throws {
        let v = try Vectors.load("media-headers.json")
        for c in try v.list("packets") {
            let header = MediaHeader(
                type: try #require(MediaPacketType(rawValue: UInt8(try c.int("type")))), streamId: UInt16(try c.int("streamId")),
                frameNo: UInt32(try c.int("frameNo")), fragIdx: UInt16(try c.int("fragIdx")), fragCnt: UInt16(try c.int("fragCnt")),
                isKeyframe: try c.bool("keyframe"), ptsMs: UInt32(try c.int("ptsMs"))
            )
            let packet = MediaPacket(header: header, payload: try c.bytes("payloadHex"))
            #expect(try packet.encode() == (try c.bytes("hex")), label(c))
            #expect(try MediaPacket.decode(try c.bytes("hex")) == packet)
        }
        for c in try v.list("invalidPackets") {
            let bytes = try c.bytes("hex")
            expectWireError(try c.str("error")) { _ = try MediaPacket.decode(bytes) }
        }
        for c in try v.list("packetizer") {
            let packetizer = Packetizer(streamId: UInt16(try c.int("streamId")), maxPayload: try c.int("maxPayload"))
            let packets = try packetizer.packetize(
                frame: try c.bytes("frameHex"), frameNo: UInt32(try c.int("frameNo")), ptsMs: UInt32(try c.int("ptsMs")),
                isKeyframe: try c.bool("keyframe")
            )
            let expected = try #require(c["packetsHex"] as? [String])
            #expect(try packets.map { WireHex.encode(try $0.encode()) } == expected, label(c))
        }
    }

    @Test func nackRoundTripAndVectors() throws {
        let v = try Vectors.load("media-headers.json")
        for c in try v.list("nack") {
            let entries = try c.list("entries").map { NackEntry(frameNo: UInt32(try $0.int("frameNo")), fragIdx: UInt16(try $0.int("fragIdx"))) }
            #expect(try NackPayload.encode(entries) == (try c.bytes("payloadHex")), label(c))
            #expect(try NackPayload.decode(try c.bytes("payloadHex")) == entries)
        }
        for c in try v.list("invalidNack") {
            let bytes = try c.bytes("payloadHex")
            expectWireError(try c.str("error")) { _ = try NackPayload.decode(bytes) }
        }
        let packet = try MediaPacket.nack(streamId: 4, entries: [NackEntry(frameNo: 1, fragIdx: 2)])
        let decoded = try MediaPacket.decode(try packet.encode())
        #expect(decoded.header.type == .nack)
        #expect(try NackPayload.decode(decoded.payload) == [NackEntry(frameNo: 1, fragIdx: 2)])
    }

    @Test func nackEncodeEnforcesCountBounds() {
        expectWireError("invalidNackCount") { _ = try NackPayload.encode([]) }
        let tooMany = (0..<65).map { NackEntry(frameNo: UInt32($0), fragIdx: 0) }
        expectWireError("invalidNackCount") { _ = try NackPayload.encode(tooMany) }
    }
}
