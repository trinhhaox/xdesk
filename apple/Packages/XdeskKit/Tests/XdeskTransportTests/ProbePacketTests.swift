#if DEBUG
import Testing
import XdeskWire
@testable import XdeskTransport

@Suite struct ProbePacketTests {
    @Test func probeRoundTripsWithAndWithoutNonce() throws {
        let plain = try MediaPacket.decode(try MediaPunch.packet(streamId: 3).encode())
        #expect(plain.header.type == .probe && plain.payload.isEmpty && MediaPunch.isProbe(plain))
        let withNonce = try MediaPacket.decode(try MediaPunch.packet(streamId: 3, nonce: 0x0123_4567_89AB_CDEF).encode())
        #expect(withNonce.payload == [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF] && MediaPunch.isProbe(withNonce))
    }

    @Test func probeWithOddPayloadLengthIsNotAccepted() {
        let bad = MediaPacket(header: MediaHeader(type: .probe, streamId: 3, frameNo: 0), payload: [1, 2, 3])
        #expect(!MediaPunch.isProbe(bad))
    }

    @Test func probeLiteralBytesMatchSpecExample() throws {
        let bytes = try MediaPunch.packet(streamId: 3, nonce: 0x0123_4567_89AB_CDEF).encode()
        #expect(WireHex.encode(bytes) == "01500003" + "00000000" + "0000" + "0001" + "00000000" + "0123456789abcdef")
    }
}
#endif
