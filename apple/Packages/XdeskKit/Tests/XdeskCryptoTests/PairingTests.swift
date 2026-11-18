import CryptoKit
import Foundation
import Testing
@testable import XdeskCrypto

struct PairingTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let tokenBytes = [UInt8](repeating: 0x11, count: 32)

    @Test func tokenLifecycle() throws {
        var issuer = PairingTokenIssuer()
        #expect(issuer.activeToken(now: t0) == nil)
        let token = try issuer.issue(now: t0)
        #expect(token.bytes.count == 32 && token.expiresAt == t0 + 120)
        #expect(issuer.activeToken(now: t0 + 119)?.bytes == token.bytes)
        #expect(issuer.activeToken(now: t0 + 120) == nil)
        let expired = issuer.consume(matching: token.bytes, now: t0 + 121)
        #expect(!expired)
    }

    @Test func tokenIsSingleUseAndMatchesExactly() throws {
        var issuer = PairingTokenIssuer()
        let token = try issuer.issue(now: t0, bytes: tokenBytes)
        var wrong = token.bytes
        wrong[31] ^= 1
        let truncated = Array(token.bytes.dropLast())
        let wrongOk = issuer.consume(matching: wrong, now: t0 + 1)
        let truncatedOk = issuer.consume(matching: truncated, now: t0 + 1)
        let firstOk = issuer.consume(matching: token.bytes, now: t0 + 2)
        let secondOk = issuer.consume(matching: token.bytes, now: t0 + 3)
        #expect(!wrongOk && !truncatedOk)
        #expect(firstOk)
        #expect(!secondOk)
        #expect(issuer.activeToken(now: t0 + 3) == nil)
    }

    @Test func newTokenInvalidatesOldAndRandomTokensDiffer() throws {
        var issuer = PairingTokenIssuer()
        let first = try issuer.issue(now: t0)
        let second = try issuer.issue(now: t0)
        #expect(first.bytes != second.bytes)
        let oldOk = issuer.consume(matching: first.bytes, now: t0)
        #expect(!oldOk)
        #expect(throws: CryptoError.invalidLength) { _ = try issuer.issue(now: t0, bytes: [1]) }
    }

    @Test func uriRoundTrip() throws {
        let host = [UInt8](repeating: 0xFB, count: 32)
        let uri = try PairingURI(hostPublicKey: host, token: tokenBytes, addresses: ["192.168.1.5:7878", "[fe80::1]:7878"])
        #expect(uri.string.hasPrefix("xdesk://pair?h="))
        #expect(!uri.string.contains("=="))
        #expect(try PairingURI.parse(uri.string) == uri)
        #expect(uri.string.contains("&a=192.168.1.5:7878"))
    }

    @Test func uriParsesKnownString() throws {
        let uri = try PairingURI.parse(
            "xdesk://pair?h=\(Base64URL.encode([UInt8](repeating: 0, count: 32)))&t=\(Base64URL.encode(tokenBytes))&a=host.local:7878&x=ignored")
        #expect(uri.addresses == ["host.local:7878"])
        #expect(uri.token == tokenBytes)
    }

    @Test func uriRejectsMalformed() {
        let k = Base64URL.encode([UInt8](repeating: 1, count: 32))
        let bad = [
            "", "http://pair?h=\(k)&t=\(k)&a=x:1", "xdesk://other?h=\(k)&t=\(k)&a=x:1", "xdesk://pair?t=\(k)&a=x:1",
            "xdesk://pair?h=\(k)&t=\(k)", "xdesk://pair?h=\(k)&h=\(k)&t=\(k)&a=x:1", "xdesk://pair?h=AAAA&t=\(k)&a=x:1",
            "xdesk://pair?h=\(k)&t=\(k)==&a=x:1", "xdesk://pair?h=\(k)&t=\(k)&a=",
            "xdesk://pair?h=\(k)&t=\(k)&a=a:1&a=b:1&a=c:1&a=d:1&a=e:1", "xdesk://pair/x?h=\(k)&t=\(k)&a=x:1",
            "xdesk://pair?h=\(k)&t=\(k)&a=nohost", "xdesk://pair?h=\(k)&t=\(k)&a=host:0", "xdesk://pair?h=\(k)&t=\(k)&a=host:65536",
        ]
        for text in bad { #expect(throws: CryptoError.invalidPairingURI, "\(text)") { _ = try PairingURI.parse(text) } }
    }

    @Test func base64UrlRoundTripAndStrictness() {
        for length in 0...5 {
            let bytes = (0..<length).map { UInt8(250 - $0) }
            #expect(Base64URL.decode(Base64URL.encode(bytes)) == bytes)
        }
        #expect(Base64URL.encode([0xFB, 0xFF]) == "-_8")
        #expect(Base64URL.decode("-_8=") == nil)
        #expect(Base64URL.decode("+/8") != nil)
    }

    @Test(arguments: [
        "192.168.1.5:7878", "10.0.0.1:1", "host.local:65535", "my-mac.example.com:7878", "a:80", "[fe80::1]:7878", "[::1]:9", "[2001:db8::8a2e:370:7334]:443",
    ])
    func validAddressesAreAccepted(address: String) throws {
        let uri = try PairingURI(hostPublicKey: [UInt8](repeating: 1, count: 32), token: tokenBytes, addresses: [address])
        #expect(uri.addresses == [address])
    }

    @Test(arguments: [
        "127.0.0.1", "127.0.0.1:0", "127.0.0.1:65536", "127.0.0.1:-1", "127.0.0.1:+80", "127.0.0.1:80a", "999.1.1.1:80", "1.2.3:80",
        "1.2.3.4.5:80", "host:port", ":80", "[::1]", "[::1]80", "::1:80", "[fe80::1%en0]:80", "[12345::1]:80", "[1.2.3.4]:80",
        "user@host:80", "http://host:80", "host/path:80", "host:80/path", "ho st:80", "host_name:80", "-host:80", "host-:80", "host..local:80",
        ".host:80", "host.:80", "ho\u{0}st:80", "bücher.local:80", "host:8 0", "a:b:80", "[::1]:80:90",
        String(repeating: "a", count: 64) + ".com:80", String(repeating: "a.", count: 130) + "com:80",
    ])
    func invalidAddressesAreRejected(address: String) {
        #expect(throws: CryptoError.invalidPairingURI) {
            _ = try PairingURI(hostPublicKey: [UInt8](repeating: 1, count: 32), token: tokenBytes, addresses: [address])
        }
    }

    @Test func secretsAreRedactedFromEveryTextualRepresentation() throws {
        var issuer = PairingTokenIssuer()
        let token = try issuer.issue(now: t0, bytes: tokenBytes)
        let uri = try PairingURI(hostPublicKey: [UInt8](repeating: 0xFB, count: 32), token: tokenBytes, addresses: ["h:1"])
        let keys = SessionKeys.derive(
            initiatorToResponder: fixedKey(1), responderToInitiator: fixedKey(2), handshakeHash: [UInt8](repeating: 3, count: 32), role: .initiator)
        let identity = DeviceIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey())
        let secrets: [(Any, [String])] = [
            (token, [Base64URL.encode(tokenBytes), "17, 17"]), (uri, [Base64URL.encode(tokenBytes), "h:1"]),
            (keys, ["tcpSend", "SymmetricKey"]), (identity, ["privateKey", Base64URL.encode(identity.publicKey)]),
        ]
        for (value, leaks) in secrets {
            var dumped = ""
            dump(value, to: &dumped)
            #expect("\(value)".contains("<redacted>") && String(reflecting: value).contains("<redacted>"))
            for text in ["\(value)", String(reflecting: value), dumped] {
                for leak in leaks { #expect(!text.contains(leak), "\(leak) in \(text)") }
            }
        }
    }
}
