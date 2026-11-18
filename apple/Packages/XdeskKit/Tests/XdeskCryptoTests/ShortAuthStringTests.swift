import CryptoKit
import Testing
@testable import XdeskCrypto

struct ShortAuthStringTests {
    private let e = [UInt8](repeating: 1, count: 32)
    private let s = [UInt8](repeating: 2, count: 32)
    private let n = [UInt8](repeating: 3, count: 16)

    @Test func commitmentBindsEveryField() throws {
        let c = try ShortAuthString.commitment(ephemeralKey: e, staticKey: s, nonce: n)
        #expect(c.count == 32)
        #expect(try ShortAuthString.verify(commitment: c, ephemeralKey: e, staticKey: s, nonce: n))
        #expect(try !ShortAuthString.verify(commitment: c, ephemeralKey: [UInt8](repeating: 9, count: 32), staticKey: s, nonce: n))
        #expect(try !ShortAuthString.verify(commitment: c, ephemeralKey: e, staticKey: [UInt8](repeating: 9, count: 32), nonce: n))
        #expect(try !ShortAuthString.verify(commitment: c, ephemeralKey: e, staticKey: s, nonce: [UInt8](repeating: 9, count: 16)))
        #expect(try !ShortAuthString.verify(commitment: Array(c.dropLast()), ephemeralKey: e, staticKey: s, nonce: n))
        #expect(throws: CryptoError.invalidLength) { _ = try ShortAuthString.commitment(ephemeralKey: [1], staticKey: s, nonce: n) }
    }

    @Test func codeIsDeterministicAndBoundToHashAndNonce() throws {
        let h = [UInt8](repeating: 4, count: 32)
        let code = try ShortAuthString.code(messageTwoHash: h, nonce: n)
        #expect(code < 1_000_000)
        #expect(try ShortAuthString.code(messageTwoHash: h, nonce: n) == code)
        let changed = try (0..<20).map { try ShortAuthString.code(messageTwoHash: h, nonce: [UInt8](repeating: UInt8($0), count: 16)) }
        #expect(Set(changed).count > 15)
        #expect(throws: CryptoError.invalidLength) { _ = try ShortAuthString.code(messageTwoHash: [1], nonce: n) }
    }

    @Test func formatPadsAndGroups() {
        #expect(ShortAuthString.format(7) == "000 007")
        #expect(ShortAuthString.format(123_456) == "123 456")
        #expect(ShortAuthString.format(999_999) == "999 999")
    }

    @Test func codeDistributionIsRoughlyUniform() throws {
        var buckets = [Int](repeating: 0, count: 10)
        for i in 0..<2000 {
            let h = Array(SHA256.hash(data: [UInt8(i & 0xFF), UInt8(i >> 8)]))
            buckets[Int(try ShortAuthString.code(messageTwoHash: h, nonce: n) / 100_000)] += 1
        }
        #expect(buckets.allSatisfy { $0 > 120 && $0 < 280 })
    }

    /// XX + SAS đầy đủ: hai bên đồng ý; MITM hai phiên Noise riêng thì mã lệch.
    @Test func endToEndAgreementAndMitmMismatch() throws {
        let nonce = ShortAuthString.randomNonce()
        let honest = try runXX(initiatorNonce: nonce, responderStatic: Curve25519.KeyAgreement.PrivateKey())
        #expect(honest.initiatorCode == honest.responderCode)
        #expect(honest.commitmentValid)

        // MITM: initiator nói chuyện với M, M nói chuyện với host bằng khoá khác.
        let sessionA = try runXX(initiatorNonce: nonce, responderStatic: Curve25519.KeyAgreement.PrivateKey())
        let sessionB = try runXX(initiatorNonce: ShortAuthString.randomNonce(), responderStatic: Curve25519.KeyAgreement.PrivateKey())
        #expect(sessionA.initiatorCode != sessionB.responderCode)
    }

    private func runXX(
        initiatorNonce: [UInt8], responderStatic: Curve25519.KeyAgreement.PrivateKey
    ) throws -> (initiatorCode: UInt32, responderCode: UInt32, commitmentValid: Bool) {
        let iStatic = Curve25519.KeyAgreement.PrivateKey()
        var i = try NoiseHandshakeState(pattern: .xx, role: .initiator, staticKey: iStatic)
        var r = try NoiseHandshakeState(pattern: .xx, role: .responder, staticKey: responderStatic)
        let m1 = try i.writeMessage()
        let initiatorEphemeral = try unwrap(i.localEphemeralKey)
        let commitment = try ShortAuthString.commitment(
            ephemeralKey: initiatorEphemeral, staticKey: Array(iStatic.publicKey.rawRepresentation), nonce: initiatorNonce)
        _ = try r.readMessage(m1)
        _ = try i.readMessage(try r.writeMessage())
        let hello = try HandshakePayload(role: .viewer, deviceName: "v", sasNonce: initiatorNonce).encode()
        let received = try HandshakePayload.decode(try r.readMessage(try i.writeMessage(payload: hello)))
        let nonce = try #require(received.sasNonce)
        let seenEphemeral = try unwrap(r.remoteEphemeralKey), seenStatic = try unwrap(r.remoteStaticKey)
        let valid = try ShortAuthString.verify(commitment: commitment, ephemeralKey: seenEphemeral, staticKey: seenStatic, nonce: nonce)
        let hashI = try unwrap(i.messageTwoHash), hashR = try unwrap(r.messageTwoHash)
        return (try ShortAuthString.code(messageTwoHash: hashI, nonce: initiatorNonce),
                try ShortAuthString.code(messageTwoHash: hashR, nonce: nonce), valid)
    }

    /// Hồi quy C1 (rà soát 261119): MITM từng mài `deviceName` trong message 3 để `code_R == code_I`.
    /// Giờ mã chỉ phụ thuộc hash sau message 2 + nonce đã cam kết, nên mọi payload message 3 cho cùng một mã.
    @Test func grindingTheMessageThreePayloadCannotChangeTheCode() throws {
        let iStatic = try privateKey((0..<32).map { UInt8($0 + 1) }), rStatic = try privateKey((0..<32).map { UInt8($0 + 50) })
        let iEphemeral = try privateKey((0..<32).map { UInt8($0 + 100) }), rEphemeral = try privateKey((0..<32).map { UInt8($0 + 150) })
        var codes = Set<UInt32>()
        var finalHashes = Set<[UInt8]>()
        for attempt in 0..<300 {
            var i = try NoiseHandshakeState(
                pattern: .xx, role: .initiator, staticKey: iStatic, remoteStaticKey: nil, psk: nil,
                prologue: NoiseHandshakeState.defaultPrologue, ephemeralOverride: iEphemeral)
            var r = try NoiseHandshakeState(
                pattern: .xx, role: .responder, staticKey: rStatic, remoteStaticKey: nil, psk: nil,
                prologue: NoiseHandshakeState.defaultPrologue, ephemeralOverride: rEphemeral)
            _ = try r.readMessage(try i.writeMessage())
            _ = try i.readMessage(try r.writeMessage(payload: try HandshakePayload(role: .host, deviceName: "Mac").encode()))
            let hello = try HandshakePayload(role: .viewer, deviceName: "iPad \(attempt)", sasNonce: n).encode()
            let revealed = try #require(HandshakePayload.decode(try r.readMessage(try i.writeMessage(payload: hello))).sasNonce)
            let hashTwo = try unwrap(r.messageTwoHash)
            codes.insert(try ShortAuthString.code(messageTwoHash: hashTwo, nonce: revealed))
            finalHashes.insert(r.handshakeHash)
        }
        #expect(finalHashes.count == 300, "payload message 3 vẫn đổi hash cuối (đầu vào cũ, đã bị phá)")
        #expect(codes.count == 1, "mã không được phụ thuộc payload message 3")
    }

    @Test func messageTwoHashIsUnavailableBeforeMessageTwoAndEqualOnBothSides() throws {
        var i = try NoiseHandshakeState(pattern: .xx, role: .initiator, staticKey: Curve25519.KeyAgreement.PrivateKey())
        var r = try NoiseHandshakeState(pattern: .xx, role: .responder, staticKey: Curve25519.KeyAgreement.PrivateKey())
        let m1 = try i.writeMessage()
        _ = try r.readMessage(m1)
        let beforeI = i.messageTwoHash, beforeR = r.messageTwoHash
        #expect(beforeI == nil && beforeR == nil)
        let m2 = try r.writeMessage()
        _ = try i.readMessage(m2)
        let hashI = try unwrap(i.messageTwoHash), hashR = r.messageTwoHash, current = i.handshakeHash
        #expect(hashI.count == 32 && hashI == hashR && hashI == current)
        _ = try r.readMessage(try i.writeMessage())
        let afterI = i.messageTwoHash, finalHash = i.handshakeHash
        #expect(afterI == hashI && finalHash != hashI)
    }
}
