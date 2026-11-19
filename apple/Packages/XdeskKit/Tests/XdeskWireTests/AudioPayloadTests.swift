import Testing
@testable import XdeskWire

@Suite struct AudioPayloadTests {
    @Test func pcmRoundTripAndHeaderBytes() throws {
        let data = [UInt8](repeating: 0x7F, count: 960)
        let payload = AudioPayload(codec: .pcm, holdMs: 258, data: data)
        let bytes = try payload.encode()
        #expect(Array(bytes.prefix(3)) == [0x00, 0x01, 0x02])
        #expect(try AudioPayload.decode(bytes) == payload)
        #expect(payload.frameCount == 240)
    }

    @Test func packetIsUnfragmentedAudioType() throws {
        let packet = try AudioPayload(codec: .aacEld, holdMs: 3, data: [1, 2, 3]).mediaPacket(streamId: 3, sequence: 9, ptsMs: 5000)
        let wire = try packet.encode()
        #expect(Array(wire.prefix(16)) == [0x01, 0x20, 0, 3, 0, 0, 0, 9, 0, 0, 0, 1, 0, 0, 0x13, 0x88])
        let back = try MediaPacket.decode(wire)
        #expect(back.header.type == .audio && back.header.fragCnt == 1 && !back.header.isKeyframe)
        #expect(try AudioPayload.decode(back.payload).frameCount == 512)
    }

    @Test func rejectsBadPayloads() {
        #expect(throws: WireError.invalidField("audio.codec")) { try AudioPayload.decode([0x09, 0, 0, 1]) }
        #expect(throws: WireError.emptyPayload) { try AudioPayload.decode([0x00, 0, 0]) }
        #expect(throws: WireError.invalidField("audio.pcm.length")) { try AudioPayload.decode([0x00, 0, 0, 1, 2, 3]) }
        #expect(throws: WireError.self) { try AudioPayload.decode([0x00, 0]) }
        #expect(throws: WireError.payloadTooLarge(1190)) {
            try AudioPayload(codec: .pcm, data: [UInt8](repeating: 0, count: 1190)).encode()
        }
    }

    @Test func capabilityMapping() {
        #expect(AudioWireCodec.pcm.capability == .audioPCM)
        #expect(AudioWireCodec.aacEld.capability == .audioAACELD)
    }

    @Test func sharedVectors() throws {
        let v = try Vectors.load("audio-payloads.json")
        for c in try v.list("payloads") {
            let codec = try #require(AudioWireCodec(rawValue: UInt8(try c.int("codec"))))
            let payload = AudioPayload(codec: codec, holdMs: UInt16(try c.int("holdMs")), data: try c.bytes("dataHex"))
            #expect(try payload.encode() == (try c.bytes("hex")), label(c))
            #expect(try AudioPayload.decode(try c.bytes("hex")) == payload, label(c))
            let packet = try payload.mediaPacket(
                streamId: UInt16(try c.int("streamId")), sequence: UInt32(try c.int("sequence")), ptsMs: UInt32(try c.int("ptsMs")))
            #expect(try packet.encode() == (try c.bytes("packetHex")), label(c))
        }
        for c in try v.list("invalidPayloads") {
            let bytes = try c.bytes("hex")
            expectWireError(try c.str("error")) { _ = try AudioPayload.decode(bytes) }
        }
    }
}
