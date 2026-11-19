import Testing
@testable import XdeskCrypto

struct UsbHelloFrameTests {
    @Test func usbHelloCarriesThirtyTwoByteHostKey() throws {
        let key = [UInt8](0..<32)
        let encoded = HandshakeFrame.usbHello(key).encode()
        #expect(encoded == [0x03] + key)
        #expect(try HandshakeFrame.decode(encoded) == .usbHello(key))
    }

    @Test func usbHelloRejectsWrongLengths() {
        for length in [0, 31, 33, 64] {
            #expect(throws: CryptoError.invalidHandshakeFrame) { _ = try HandshakeFrame.decode([0x03] + [UInt8](repeating: 1, count: length)) }
        }
    }
}
