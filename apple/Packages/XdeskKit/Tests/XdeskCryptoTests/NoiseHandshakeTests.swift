import CryptoKit
import Testing
@testable import XdeskCrypto

struct NoiseHandshakeTests {
    private let psk = [UInt8](repeating: 7, count: 32)
    private let initiatorStatic = Curve25519.KeyAgreement.PrivateKey()
    private let responderStatic = Curve25519.KeyAgreement.PrivateKey()

    private func initiator(
        _ pattern: NoisePattern, psk overridePsk: [UInt8]? = nil, prologue: [UInt8] = NoiseHandshakeState.defaultPrologue
    ) throws -> NoiseHandshakeState {
        try NoiseHandshakeState(
            pattern: pattern, role: .initiator, staticKey: initiatorStatic,
            remoteStaticKey: pattern == .ik ? Array(responderStatic.publicKey.rawRepresentation) : nil,
            psk: pattern.usesPresharedKey ? (overridePsk ?? psk) : nil, prologue: prologue)
    }

    private func responder(_ pattern: NoisePattern, psk overridePsk: [UInt8]? = nil) throws -> NoiseHandshakeState {
        try NoiseHandshakeState(
            pattern: pattern, role: .responder, staticKey: responderStatic, psk: pattern.usesPresharedKey ? (overridePsk ?? psk) : nil)
    }

    private func complete(_ i: inout NoiseHandshakeState, _ r: inout NoiseHandshakeState) throws {
        var turn = 0
        while !i.isComplete {
            let payload = Array("payload-\(turn)".utf8)
            // Message 0 của XX/XXpsk3 phải rỗng (chưa mã hoá); IK mang payload được.
            let first = turn == 0 && i.pattern != .ik ? [] : payload
            if turn % 2 == 0 {
                let received = try r.readMessage(try i.writeMessage(payload: first))
                #expect(received == first)
            } else {
                let received = try i.readMessage(try r.writeMessage(payload: payload))
                #expect(received == payload)
            }
            turn += 1
        }
    }

    @Test(arguments: NoisePattern.allCases)
    func roundTripAgreesOnKeysAndHash(pattern: NoisePattern) throws {
        var i = try initiator(pattern), r = try responder(pattern)
        try complete(&i, &r)
        let responderDone = r.isComplete, hashI = i.handshakeHash, hashR = r.handshakeHash
        let remoteOfI = i.remoteStaticKey, remoteOfR = r.remoteStaticKey
        #expect(responderDone)
        #expect(hashI == hashR)
        #expect(remoteOfI == Array(responderStatic.publicKey.rawRepresentation))
        #expect(remoteOfR == Array(initiatorStatic.publicKey.rawRepresentation))
        let ik = try i.sessionKeys(), rk = try r.sessionKeys()
        #expect(ik.tcpSend.bytes == rk.tcpReceive.bytes)
        #expect(ik.tcpReceive.bytes == rk.tcpSend.bytes)
        #expect(ik.udpSend.bytes == rk.udpReceive.bytes)
        #expect(ik.udpReceive.bytes == rk.udpSend.bytes)
        let all = [ik.tcpSend, ik.tcpReceive, ik.udpSend, ik.udpReceive].map(\.bytes)
        #expect(Set(all).count == 4)
    }

    @Test func pskMismatchFailsWhenResponderReadsMessage3() throws {
        var i = try initiator(.xxPsk3), r = try responder(.xxPsk3, psk: [UInt8](repeating: 8, count: 32))
        _ = try r.readMessage(try i.writeMessage())
        _ = try i.readMessage(try r.writeMessage())
        let m3 = try i.writeMessage(payload: [1])
        #expect(throws: CryptoError.authenticationFailed) { _ = try r.readMessage(m3) }
    }

    @Test func prologueMismatchFails() throws {
        var i = try initiator(.xx, prologue: Array("other".utf8)), r = try responder(.xx)
        _ = try r.readMessage(try i.writeMessage())
        let m2 = try r.writeMessage()
        #expect(throws: CryptoError.authenticationFailed) { _ = try i.readMessage(m2) }
    }

    @Test func tamperedMessageIsRejectedAndStateIsKept() throws {
        var i = try initiator(.xx), r = try responder(.xx)
        _ = try r.readMessage(try i.writeMessage())
        var m2 = try r.writeMessage(payload: [9, 9])
        let good = m2
        m2[m2.count - 1] ^= 1
        #expect(throws: CryptoError.authenticationFailed) { _ = try i.readMessage(m2) }
        #expect(try i.readMessage(good) == [9, 9])
    }

    @Test func ikRejectsInitiatorWithWrongResponderKey() throws {
        let wrong = Array(Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation)
        var i = try NoiseHandshakeState(pattern: .ik, role: .initiator, staticKey: initiatorStatic, remoteStaticKey: wrong)
        var r = try NoiseHandshakeState(pattern: .ik, role: .responder, staticKey: responderStatic)
        let m1 = try i.writeMessage()
        #expect(throws: CryptoError.authenticationFailed) { _ = try r.readMessage(m1) }
    }

    @Test func ikResponderLearnsInitiatorKeyAfterFirstMessage() throws {
        var i = try initiator(.ik), r = try responder(.ik)
        _ = try r.readMessage(try i.writeMessage(payload: [1]))
        let learned = r.remoteStaticKey, done = r.isComplete
        #expect(learned == Array(initiatorStatic.publicKey.rawRepresentation))
        #expect(!done)
    }

    @Test func wrongTurnAndCompletedStateAreErrors() throws {
        var i = try initiator(.xx), r = try responder(.xx)
        #expect(throws: CryptoError.wrongTurn) { _ = try r.writeMessage() }
        #expect(throws: CryptoError.wrongTurn) { _ = try i.readMessage([0]) }
        #expect(throws: CryptoError.handshakeIncomplete) { _ = try i.splitKeys() }
        try complete(&i, &r)
        #expect(throws: CryptoError.handshakeComplete) { _ = try i.writeMessage() }
        #expect(throws: CryptoError.handshakeComplete) { _ = try r.readMessage([0]) }
    }

    @Test func truncatedAndOversizedMessages() throws {
        var i = try initiator(.xx), r = try responder(.xx)
        #expect(throws: CryptoError.messageTooShort) { _ = try r.readMessage([1, 2, 3]) }
        #expect(throws: CryptoError.messageTooLarge) { _ = try r.readMessage([UInt8](repeating: 0, count: 65_536)) }
        _ = try r.readMessage(try i.writeMessage())
        #expect(throws: CryptoError.messageTooLarge) {
            _ = try r.writeMessage(payload: [UInt8](repeating: 0, count: 65_535))
        }
    }

    @Test func lowOrderEphemeralIsRejected() throws {
        var i = try initiator(.xx), r = try responder(.xx)
        _ = try r.readMessage(try i.writeMessage())
        _ = try r.writeMessage()
        let forged = [UInt8](repeating: 0, count: 32) + [UInt8](repeating: 1, count: 80)
        #expect(throws: CryptoError.invalidDiffieHellman) { _ = try i.readMessage(forged) }
    }

    @Test func configurationValidation() throws {
        #expect(throws: CryptoError.missingPresharedKey) {
            _ = try NoiseHandshakeState(pattern: .xxPsk3, role: .initiator, staticKey: initiatorStatic)
        }
        #expect(throws: CryptoError.invalidPresharedKeyLength) {
            _ = try NoiseHandshakeState(pattern: .xxPsk3, role: .initiator, staticKey: initiatorStatic, psk: [1])
        }
        #expect(throws: CryptoError.unexpectedKeyForPattern) {
            _ = try NoiseHandshakeState(pattern: .xx, role: .initiator, staticKey: initiatorStatic, psk: psk)
        }
        #expect(throws: CryptoError.missingRemoteStaticKey) {
            _ = try NoiseHandshakeState(pattern: .ik, role: .initiator, staticKey: initiatorStatic)
        }
        #expect(throws: CryptoError.invalidPublicKey) {
            _ = try NoiseHandshakeState(pattern: .ik, role: .initiator, staticKey: initiatorStatic, remoteStaticKey: [1, 2])
        }
    }

    @Test(arguments: [NoisePattern.xx, .xxPsk3])
    func firstMessagePayloadMustBeEmptyOnWriteAndOnRead(pattern: NoisePattern) throws {
        var i = try initiator(pattern), r = try responder(pattern)
        #expect(throws: CryptoError.invalidHandshakePayload) { _ = try i.writeMessage(payload: [1]) }
        // Bên gửi bỏ qua kiểm tra (vector cacophony) vẫn bị bên đọc bình thường từ chối, và trạng thái bên đọc giữ nguyên.
        var sloppy = try NoiseHandshakeState(
            pattern: pattern, role: .initiator, staticKey: initiatorStatic, remoteStaticKey: nil,
            psk: pattern.usesPresharedKey ? psk : nil, prologue: NoiseHandshakeState.defaultPrologue,
            ephemeralOverride: Curve25519.KeyAgreement.PrivateKey())
        let withPayload = try sloppy.writeMessage(payload: [1, 2, 3])
        #expect(throws: CryptoError.invalidHandshakePayload) { _ = try r.readMessage(withPayload) }
        let clean = try i.writeMessage()
        #expect(try r.readMessage(clean) == [])
    }

    @Test func ikStillCarriesAPayloadInMessageOne() throws {
        var i = try initiator(.ik), r = try responder(.ik)
        let received = try r.readMessage(try i.writeMessage(payload: [4, 5, 6]))
        #expect(received == [4, 5, 6])
    }

    @Test func lowOrderPointsInEveryPositionMapToCryptoError() throws {
        let lowOrder: [[UInt8]] = [
            [UInt8](repeating: 0, count: 32), [1] + [UInt8](repeating: 0, count: 31),
            [UInt8](repeating: 0xFF, count: 31) + [0x7F], [0xEC] + [UInt8](repeating: 0xFF, count: 30) + [0x7F],
        ]
        for point in lowOrder {
            var i = try initiator(.xx), r = try responder(.xx)
            _ = try r.readMessage(try i.writeMessage())
            _ = try r.writeMessage()
            #expect(throws: CryptoError.self) { _ = try i.readMessage(point + [UInt8](repeating: 1, count: 80)) }
        }
    }
}
