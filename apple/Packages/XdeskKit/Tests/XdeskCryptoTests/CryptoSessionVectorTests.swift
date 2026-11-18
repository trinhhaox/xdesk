import CryptoKit
import Foundation
import Testing
@testable import XdeskCrypto

/// Kiểm `protocol/test-vectors/crypto-session.json` (sinh bởi tools/gen-test-vectors; Kotlin phase 07 dùng cùng file).
struct CryptoSessionVectorTests {
    private func file() throws -> JSONDict { try Vectors.load("crypto-session.json") }

    private func dict(_ parent: JSONDict, _ key: String) throws -> JSONDict { try #require(parent[key] as? JSONDict) }

    @Test func sessionKeys() throws {
        let v = try dict(file(), "sessionKeys")
        let expected = try dict(v, "initiator")
        let initiator = SessionKeys.derive(
            initiatorToResponder: SymmetricKey(data: try v.hex("initiatorToResponder")),
            responderToInitiator: SymmetricKey(data: try v.hex("responderToInitiator")),
            handshakeHash: try v.hex("handshakeHash"), role: .initiator)
        #expect(initiator.tcpSend.bytes == (try expected.hex("tcpSend")))
        #expect(initiator.tcpReceive.bytes == (try expected.hex("tcpReceive")))
        #expect(initiator.udpSend.bytes == (try expected.hex("udpSend")))
        #expect(initiator.udpReceive.bytes == (try expected.hex("udpReceive")))
    }

    @Test func datagrams() throws {
        let v = try dict(file(), "datagram")
        let key = SymmetricKey(data: try v.hex("key"))
        let header = try v.hex("headerHex")
        var sender = DatagramSender(key: key)
        let steps = try v.list("packets")
        for (index, step) in steps.enumerated() {
            for _ in 0..<(try step.int("rekeysBefore")) { try sender.rekey() }
            let sealed = try sender.seal(header: header, payload: try step.hex("payloadHex"))
            #expect(sealed == (try step.hex("datagramHex")), "packet \(index)")
        }
        var receiver = DatagramReceiver(key: key)
        for entry in try v.list("receiveScript") {
            let datagram = try steps[entry.int("packet")].hex("datagramHex")
            let outcome = try entry.str("result")
            if outcome == "ok" {
                let expectedPayload = try entry.hex("payloadHex")
                #expect(try receiver.open(datagram).payload == expectedPayload)
            } else {
                let error = #expect(throws: CryptoError.self) { _ = try receiver.open(datagram) }
                let name = error.map { "\($0)" }
                #expect(name == outcome)
            }
        }
    }

    @Test func streamFrames() throws {
        let v = try dict(file(), "stream")
        var sender = StreamSender(key: SymmetricKey(data: try v.hex("key")))
        var receiver = StreamReceiver(key: SymmetricKey(data: try v.hex("key")))
        let rekeyAfter = try v.int("rekeyAfterFrame")
        for (index, frame) in try v.list("frames").enumerated() {
            if index == rekeyAfter {
                sender.rekey()
                receiver.rekey()
            }
            let kind = UInt8(try frame.int("kind"))
            let sealed = try sender.seal(kind: kind, plaintext: try frame.hex("plaintextHex"))
            #expect(sealed == (try frame.hex("ciphertextHex")), "frame \(index)")
            #expect(try receiver.open(kind: kind, ciphertext: sealed) == (try frame.hex("plaintextHex")))
        }
    }

    @Test func sas() throws {
        let v = try dict(file(), "sas")
        let nonce = try v.hex("nonce")
        let commitment = try ShortAuthString.commitment(ephemeralKey: v.hex("ephemeral"), staticKey: v.hex("static"), nonce: nonce)
        #expect(commitment == (try v.hex("commitment")))
        let code = try ShortAuthString.code(messageTwoHash: v.hex("messageTwoHash"), nonce: nonce)
        #expect(Int(code) == (try v.int("code")))
        #expect(ShortAuthString.format(code) == (try v.str("display")))
        for entry in try v.list("formatCases") {
            #expect(ShortAuthString.format(UInt32(try entry.int("code"))) == (try entry.str("display")))
        }
    }

    @Test func envelopeAndPairing() throws {
        let envelope = try dict(file(), "handshakeEnvelope")
        for entry in try envelope.list("payloads") {
            let nonceHex = try entry.str("sasNonceHex")
            let payload = HandshakePayload(
                role: try #require(DeviceRole(rawValue: UInt8(try entry.int("role")))), deviceName: try entry.str("name"),
                sasNonce: nonceHex.isEmpty ? nil : Hex.decode(nonceHex))
            #expect(try payload.encode() == (try entry.hex("hex")))
            #expect(try HandshakePayload.decode(try entry.hex("hex")) == payload)
        }
        for entry in try envelope.list("frames") {
            let bytes = try entry.hex("hex")
            #expect(try HandshakeFrame.decode(bytes).encode() == bytes)
        }
        let pairing = try dict(file(), "pairing")
        let parsed = try PairingURI.parse(try pairing.str("uri"))
        #expect(parsed.hostPublicKey == (try pairing.hex("hostPublicKey")))
        #expect(parsed.token == (try pairing.hex("token")))
        #expect(parsed.addresses == (try #require(pairing["addresses"] as? [String])))
        #expect(DeviceFingerprint.make(publicKey: parsed.hostPublicKey) == (try pairing.str("fingerprint")))
    }
}
