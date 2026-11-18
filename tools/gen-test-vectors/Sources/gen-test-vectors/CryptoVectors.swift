import CryptoKit
import Foundation
import XdeskCrypto

/// Khoá/nonce cố định để Kotlin (phase 07) tái tạo từng byte. Chỉ dùng cho vector, không bao giờ cho phiên thật.
private func pattern(_ start: UInt8) -> [UInt8] { (0..<32).map { start &+ UInt8($0) } }
private let header: [UInt8] = [0x01, 0x10, 0x00, 0x03, 0x00, 0x00, 0x00, 0x2A, 0x00, 0x00, 0x80, 0x03, 0x00, 0x00, 0x13, 0x88]

func cryptoVectors() -> JSONObject {
    let split = (i2r: pattern(0x10), r2i: pattern(0x50), hash: pattern(0x90))
    let keys = SessionKeys.derive(
        initiatorToResponder: SymmetricKey(data: split.i2r), responderToInitiator: SymmetricKey(data: split.r2i),
        handshakeHash: split.hash, role: .initiator)
    let udpKey = keys.udpSend, tcpKey = keys.tcpSend
    return [
        "version": 1,
        "note": "Khoá thử nghiệm cố định; vai initiator. Responder hoán đổi send/receive.",
        "sessionKeys": [
            "initiatorToResponder": hex(split.i2r), "responderToInitiator": hex(split.r2i), "handshakeHash": hex(split.hash),
            "initiator": [
                "tcpSend": hex(keys.tcpSend.rawBytes), "tcpReceive": hex(keys.tcpReceive.rawBytes),
                "udpSend": hex(keys.udpSend.rawBytes), "udpReceive": hex(keys.udpReceive.rawBytes),
            ],
        ] as JSONObject,
        "datagram": datagramVectors(key: udpKey),
        "stream": streamVectors(key: tcpKey),
        "sas": sasVectors(),
        "handshakeEnvelope": envelopeVectors(),
        "pairing": pairingVectors(),
    ]
}

private func datagramVectors(key: SymmetricKey) -> JSONObject {
    var sender = DatagramSender(key: key)
    // (tên, số lần rekey trước khi gửi, payload): bao phủ nhảy tiến 2, 3, 4 epoch (được) và 5 epoch (từ chối).
    let plan: [(String, Int, [UInt8])] = [
        ("epoch0-counter0", 0, Array("frame-0".utf8)), ("epoch0-counter1-empty", 0, []),
        ("epoch1-counter0", 1, Array("after-rekey".utf8)),
        ("epoch3-counter0", 2, Array("jump-2".utf8)), ("epoch3-counter1", 0, Array("old-epoch".utf8)),
        ("epoch6-counter0", 3, Array("derived-previous".utf8)), ("epoch7-counter0", 1, Array("jump-4".utf8)),
        ("epoch12-counter0", 5, Array("jump-5".utf8)),
    ]
    var packets: [[UInt8]] = []
    var steps: [JSONObject] = []
    for (label, rekeys, payload) in plan {
        for _ in 0..<rekeys { unwrap("rekey") { try sender.rekey() } }
        let packet = unwrap("seal \(label)") { try sender.seal(header: header, payload: payload) }
        packets.append(packet)
        steps.append([
            "name": label, "rekeysBefore": rekeys, "epoch": Int(sender.epoch), "payloadHex": hex(payload), "datagramHex": hex(packet),
        ])
    }

    var receiver = DatagramReceiver(key: key)
    let script: [(String, Int)] = [
        ("ok", 0), ("duplicate", 0), ("ok-advances-epoch", 2), ("ok-late-previous-epoch", 1), ("duplicate-after-rekey", 2),
        ("ok-forward-jump-2-epochs", 3), ("ok-forward-jump-4-epochs", 6), ("ok-late-derived-previous-epoch", 5),
        ("epoch-older-than-previous", 4), ("forward-jump-5-too-far", 7),
    ]
    let receive = script.map { name, index -> JSONObject in
        do {
            let opened = try receiver.open(packets[index])
            return ["name": name, "packet": index, "result": "ok", "payloadHex": hex(opened.payload)]
        } catch { return ["name": name, "packet": index, "result": "\(error)"] }
    }
    return [
        "headerHex": hex(header), "key": hex(key.rawBytes),
        "note": "datagram = header | nonce u64 BE (epoch<<32|counter) | ciphertext | tag; AD = header; nonce12 = 4×00 | nonce u64 LE; "
            + "rekeysBefore = số lần sender.rekey() trước khi seal; bên nhận chấp nhận epoch mới hơn 1…4 (dẫn xuất thử), 5+ → unknownEpoch",
        "packets": steps, "receiveScript": receive,
    ]
}

private func streamVectors(key: SymmetricKey) -> JSONObject {
    var sender = StreamSender(key: key)
    var frames: [JSONObject] = []
    let plan: [(UInt8, [UInt8], String)] = [
        (0x02, Array(#"{"id":10,"t":"ping","t0":1700000000123}"#.utf8), "control-ping"),
        (0x03, [0x00, 0x01, 0x02], "bulk"),
        (0x04, [], "media-over-tcp-empty"),
        (0x02, Array(#"{"t":"pong"}"#.utf8), "control-after-rekey"),
    ]
    for (index, (kind, plaintext, name)) in plan.enumerated() {
        if index == 3 { sender.rekey() }
        let sealed = unwrap("stream \(name)") { try sender.seal(kind: kind, plaintext: plaintext) }
        frames.append(["name": name, "kind": Int(kind), "plaintextHex": hex(plaintext), "ciphertextHex": hex(sealed)])
    }
    return ["key": hex(key.rawBytes), "note": "ad = u32 BE(len=1+ciphertext.count) | kind; nonce = số thứ tự frame trong epoch; rekey sau frame 3", "frames": frames, "rekeyAfterFrame": 3]
}

private func sasVectors() -> JSONObject {
    let e = pattern(0x01), s = pattern(0x21), nonce = Array(pattern(0x41).prefix(16)), h2 = pattern(0x61)
    let commitment = unwrap("commitment") { try ShortAuthString.commitment(ephemeralKey: e, staticKey: s, nonce: nonce) }
    let code = unwrap("sas code") { try ShortAuthString.code(messageTwoHash: h2, nonce: nonce) }
    return [
        "ephemeral": hex(e), "static": hex(s), "nonce": hex(nonce), "commitment": hex(commitment),
        "messageTwoHash": hex(h2), "code": Int(code), "display": ShortAuthString.format(code),
        "formatCases": [[0, "000 000"], [7, "000 007"], [123_456, "123 456"], [999_999, "999 999"]].map { ["code": $0[0], "display": $0[1]] as JSONObject },
    ]
}

private func envelopeVectors() -> JSONObject {
    let nonce = Array(pattern(0x70).prefix(16))
    let payloads = [
        HandshakePayload(role: .host, deviceName: "Mac"),
        HandshakePayload(role: .viewer, deviceName: "iPad", sasNonce: nonce),
    ]
    return [
        "payloads": payloads.map { p -> JSONObject in
            ["role": Int(p.role.rawValue), "name": p.deviceName, "sasNonceHex": p.sasNonce.map(hex) ?? "", "hex": hex(unwrap("payload") { try p.encode() })]
        },
        "frames": [
            ["name": "begin-xx", "hex": hex(HandshakeFrame.begin(.xx).encode())],
            ["name": "begin-xxpsk3", "hex": hex(HandshakeFrame.begin(.xxPsk3).encode())],
            ["name": "begin-ik", "hex": hex(HandshakeFrame.begin(.ik).encode())],
            ["name": "commit", "hex": hex(HandshakeFrame.commit(pattern(0x80)).encode())],
            ["name": "noise", "hex": hex(HandshakeFrame.noise([0xAA, 0xBB]).encode())],
        ],
    ]
}

private func pairingVectors() -> JSONObject {
    let host = pattern(0xA0), token = pattern(0xC0)
    let uri = unwrap("uri") { try PairingURI(hostPublicKey: host, token: token, addresses: ["192.168.1.5:7878", "[fe80::1]:7878"]) }
    return [
        "hostPublicKey": hex(host), "token": hex(token), "addresses": uri.addresses, "uri": uri.string,
        "fingerprint": DeviceFingerprint.make(publicKey: host),
    ]
}

private func unwrap<T>(_ what: String, _ body: () throws -> T) -> T {
    do { return try body() } catch { fail("\(what): \(error)") }
}

private extension SymmetricKey {
    var rawBytes: [UInt8] { withUnsafeBytes { Array($0) } }
}
