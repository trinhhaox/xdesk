import Testing
@testable import XdeskCrypto

struct HandshakeEnvelopeTests {
    @Test func payloadRoundTrip() throws {
        let nonce = [UInt8](repeating: 0xAB, count: 16)
        for payload in [
            HandshakePayload(role: .host, deviceName: "Mac của Hào"),
            HandshakePayload(role: .viewer, deviceName: "", sasNonce: nonce),
        ] {
            #expect(try HandshakePayload.decode(payload.encode()) == payload)
        }
        #expect(try HandshakePayload(role: .viewer, deviceName: "iPad").encode() == [1, 1, 0, 4] + Array("iPad".utf8))
    }

    @Test func payloadRejectsMalformed() throws {
        let valid = try HandshakePayload(role: .host, deviceName: "ab").encode()
        let cases: [[UInt8]] = [
            [], [1, 0, 0], [2, 0, 0, 0], [1, 2, 0, 0], [1, 0, 2, 0], [1, 0, 0, 3, 0x61],
            valid + [0], [1, 0, 0, 2, 0xC3, 0x28], [1, 0, 1, 0] + [UInt8](repeating: 0, count: 15),
            [1, 0, 0, 65] + [UInt8](repeating: 0x61, count: 65),
        ]
        for bytes in cases {
            #expect(throws: CryptoError.invalidHandshakePayload) { _ = try HandshakePayload.decode(bytes) }
        }
        #expect(throws: CryptoError.invalidHandshakePayload) {
            _ = try HandshakePayload(role: .host, deviceName: String(repeating: "a", count: 65)).encode()
        }
        #expect(throws: CryptoError.invalidHandshakePayload) {
            _ = try HandshakePayload(role: .host, deviceName: "x", sasNonce: [1]).encode()
        }
    }

    @Test func frameRoundTripAndHex() throws {
        #expect(HandshakeFrame.begin(.xxPsk3).encode() == [0x00, 0x01, 0x02])
        let frames: [HandshakeFrame] = [.begin(.xx), .begin(.ik), .commit([UInt8](repeating: 5, count: 32)), .noise([1, 2, 3])]
        for frame in frames { #expect(try HandshakeFrame.decode(frame.encode()) == frame) }
    }

    @Test func frameRejectsMalformed() {
        let cases: [[UInt8]] = [[], [0x00], [0x00, 0x02, 0x01], [0x00, 0x01, 0x09], [0x01, 0x01], [0x02], [0x03, 0x00]]
        for bytes in cases {
            #expect(throws: CryptoError.invalidHandshakeFrame) { _ = try HandshakeFrame.decode(bytes) }
        }
    }
}
