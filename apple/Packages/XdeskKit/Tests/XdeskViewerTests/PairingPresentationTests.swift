import Testing
import XdeskCrypto
@testable import XdeskViewer

@Suite struct PairingPresentationTests {
    private func device() -> PairedDevice {
        PairedDevice(name: "Mac", publicKey: [UInt8](repeating: 7, count: 32), role: .host, createdAt: .distantPast)
    }

    @Test func badgeMappingAndReconnectRules() {
        let known = device()
        #expect(ViewerTrust.HostState.paired(known).badge == .paired)
        #expect(ViewerTrust.HostState.unknown.badge == .unpaired)
        #expect(ViewerTrust.HostState.keyChanged(expected: known).badge == .keyChanged)
        #expect(ViewerTrust.HostState.paired(known).canReconnect)
        #expect(!ViewerTrust.HostState.unknown.canReconnect)
        #expect(!ViewerTrust.HostState.keyChanged(expected: known).canReconnect)
    }

    @Test func badgeTitlesAreVietnamese() {
        #expect(HostBadge.paired.title == "Đã ghép")
        #expect(HostBadge.unpaired.title == "Chưa ghép")
        #expect(HostBadge.keyChanged.title == "Khoá đã đổi")
    }

    @Test func parsesValidUriWithWhitespace() throws {
        let uri = try PairingURI(hostPublicKey: [UInt8](repeating: 1, count: 32), token: [UInt8](repeating: 2, count: 32), addresses: ["192.168.1.2:47800"])
        let result = PairingInput.parse("  \(uri.string)\n")
        #expect(try result.get() == uri)
    }

    @Test func rejectsEmptyForeignAndBrokenInput() {
        #expect(PairingInput.parse("   ") == .failure(.empty))
        #expect(PairingInput.parse("https://example.com") == .failure(.notXdesk))
        #expect(PairingInput.parse("xdesk://pair?h=abc") == .failure(.malformed))
        #expect(PairingInput.parse("xdesk://pair?h=abc&t=zzz&a=1.2.3.4:5") == .failure(.malformed))
    }
}
