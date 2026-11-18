import Testing
@testable import XdeskTransport

@Suite struct PeerAddressPolicyTests {
    @Test func ipv4Ranges() {
        for ok in [[127, 0, 0, 1], [10, 1, 2, 3], [192, 168, 1, 9], [172, 16, 0, 1], [172, 31, 255, 1], [169, 254, 1, 1], [100, 100, 1, 1]] as [[UInt8]] {
            #expect(PeerAddressPolicy.isLocal(ipv4: ok), "\(ok)")
        }
        for bad in [[8, 8, 8, 8], [172, 32, 0, 1], [100, 63, 0, 1], [100, 128, 0, 1], [192, 169, 0, 1]] as [[UInt8]] {
            #expect(!PeerAddressPolicy.isLocal(ipv4: bad), "\(bad)")
        }
        #expect(!PeerAddressPolicy.isLocal(ipv4: [1, 2, 3]))
    }

    @Test func ipv6Ranges() {
        var loopback = [UInt8](repeating: 0, count: 16); loopback[15] = 1
        var linkLocal = [UInt8](repeating: 0, count: 16); linkLocal[0] = 0xFE; linkLocal[1] = 0x80
        var ula = [UInt8](repeating: 0, count: 16); ula[0] = 0xFD; ula[1] = 0x7A
        var mappedLan = [UInt8](repeating: 0, count: 16); mappedLan[10] = 0xFF; mappedLan[11] = 0xFF; mappedLan[12] = 192; mappedLan[13] = 168; mappedLan[14] = 1; mappedLan[15] = 5
        var mappedPublic = mappedLan; mappedPublic[12] = 8; mappedPublic[13] = 8
        var global = [UInt8](repeating: 0, count: 16); global[0] = 0x20; global[1] = 0x01
        for ok in [loopback, linkLocal, ula, mappedLan] { #expect(PeerAddressPolicy.isLocal(ipv6: ok)) }
        for bad in [mappedPublic, global] { #expect(!PeerAddressPolicy.isLocal(ipv6: bad)) }
    }
}
