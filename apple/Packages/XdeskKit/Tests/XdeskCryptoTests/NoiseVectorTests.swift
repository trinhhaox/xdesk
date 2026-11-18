import CryptoKit
import Testing
@testable import XdeskCrypto

/// Vector công khai của cacophony (xem protocol/test-vectors/noise-README.md).
struct NoiseVectorTests {
    @Test(arguments: [
        ("noise-xx.json", NoisePattern.xx),
        ("noise-xxpsk3.json", NoisePattern.xxPsk3),
        ("noise-ik.json", NoisePattern.ik),
    ])
    func cacophonyVector(file: String, pattern: NoisePattern) throws {
        let entries = try Vectors.load(file).list("vectors")
        #expect(entries.count == 1)
        for vector in entries { try run(vector, pattern: pattern) }
    }

    private func run(_ v: JSONDict, pattern: NoisePattern) throws {
        #expect(try v.str("protocol_name") == pattern.protocolName)
        let prologue = try v.hex("init_prologue")
        let psk = try (v["init_psks"] as? [String])?.first.flatMap(Hex.decode)
        var initiator = try NoiseHandshakeState(
            pattern: pattern, role: .initiator, staticKey: privateKey(v.hex("init_static")),
            remoteStaticKey: v.optionalHex("init_remote_static"), psk: psk, prologue: prologue,
            ephemeralOverride: privateKey(v.hex("init_ephemeral")))
        var responder = try NoiseHandshakeState(
            pattern: pattern, role: .responder, staticKey: privateKey(v.hex("resp_static")),
            remoteStaticKey: nil, psk: psk, prologue: prologue,
            ephemeralOverride: privateKey(v.hex("resp_ephemeral")))

        let messages = try v.list("messages")
        var index = 0
        while !initiator.isComplete {
            let isInitiatorTurn = index % 2 == 0
            let payload = try messages[index].hex("payload")
            let expected = try messages[index].hex("ciphertext")
            let wire = isInitiatorTurn ? try initiator.writeMessage(payload: payload) : try responder.writeMessage(payload: payload)
            #expect(wire == expected, "handshake message \(index)")
            let received = isInitiatorTurn ? try responder.readMessage(wire) : try initiator.readMessage(wire)
            #expect(received == payload)
            index += 1
        }
        let responderDone = responder.isComplete, initiatorHash = initiator.handshakeHash, responderHash = responder.handshakeHash
        #expect(responderDone)
        #expect(initiatorHash == (try v.hex("handshake_hash")))
        #expect(responderHash == initiatorHash)
        try runTransport(messages: messages, from: index, initiator: initiator, responder: responder)
    }

    private func runTransport(messages: [JSONDict], from start: Int, initiator: borrowing NoiseHandshakeState, responder: borrowing NoiseHandshakeState) throws {
        let keys = try initiator.splitKeys()
        var iSend = NoiseCipherState(key: keys.initiatorToResponder)
        var rRecv = NoiseCipherState(key: keys.initiatorToResponder)
        var rSend = NoiseCipherState(key: keys.responderToInitiator)
        var iRecv = NoiseCipherState(key: keys.responderToInitiator)
        let responderKeys = try responder.splitKeys()
        #expect(responderKeys.initiatorToResponder.bytes == keys.initiatorToResponder.bytes)
        #expect(responderKeys.responderToInitiator.bytes == keys.responderToInitiator.bytes)

        for index in start..<messages.count {
            let payload = try messages[index].hex("payload")
            let expected = try messages[index].hex("ciphertext")
            let fromInitiator = index % 2 == 0
            let wire = fromInitiator
                ? try iSend.encrypt(ad: [], plaintext: payload)
                : try rSend.encrypt(ad: [], plaintext: payload)
            #expect(wire == expected, "transport message \(index)")
            let plain = fromInitiator ? try rRecv.decrypt(ad: [], ciphertext: wire) : try iRecv.decrypt(ad: [], ciphertext: wire)
            #expect(plain == payload)
        }
    }
}
