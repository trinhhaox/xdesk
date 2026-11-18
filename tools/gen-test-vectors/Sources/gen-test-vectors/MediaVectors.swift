import Foundation
import XdeskWire

func mediaVectors() -> JSONObject {
    let headers: [(String, MediaHeader, [UInt8])] = [
        ("video-key-first-frag", MediaHeader(type: .video, streamId: 1, frameNo: 7, fragIdx: 0, fragCnt: 3, isKeyframe: true, ptsMs: 1000), [0x01, 0x02, 0x03]),
        ("video-delta-last-frag", MediaHeader(type: .video, streamId: 1, frameNo: 7, fragIdx: 2, fragCnt: 3, ptsMs: 1000), [0xFF]),
        ("video-max-frag-count", MediaHeader(type: .video, streamId: 65535, frameNo: 4_294_967_295, fragIdx: 2047, fragCnt: 2048, ptsMs: 4_294_967_295), [0x00]),
        ("audio-single", MediaHeader(type: .audio, streamId: 2, frameNo: 100, ptsMs: 2000), [0x10, 0x20]),
        ("video-parity-reserved", MediaHeader(type: .videoParity, streamId: 1, frameNo: 1), []),
        ("probe-empty", MediaHeader(type: .probe, streamId: 3, frameNo: 0), []),
        ("probe-nonce", MediaHeader(type: .probe, streamId: 3, frameNo: 0), [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]),
    ]
    return [
        "version": 1,
        "packets": headers.map { name, header, payload -> JSONObject in
            let bytes = encode(MediaPacket(header: header, payload: payload))
            return [
                "name": name, "type": Int(header.type.rawValue), "streamId": Int(header.streamId), "frameNo": Int(header.frameNo),
                "fragIdx": Int(header.fragIdx), "fragCnt": Int(header.fragCnt), "keyframe": header.isKeyframe,
                "ptsMs": Int(header.ptsMs), "payloadHex": hex(payload), "hex": hex(bytes),
            ]
        },
        "invalidPackets": invalidPackets(),
        "nack": nackVectors(),
        "invalidNack": invalidNack(),
        "packetizer": packetizerVectors(),
    ]
}

private func encode(_ p: MediaPacket) -> [UInt8] {
    do { return try p.encode() } catch { fail("encode packet: \(error)") }
}

private func rawHeader(ver: UInt8 = 1, type: UInt8 = 0x10, idx: UInt16 = 0, cntRaw: UInt16 = 1) -> [UInt8] {
    [ver, type] + be16(1) + be32(9) + be16(idx) + be16(cntRaw) + be32(0)
}

private func invalidPackets() -> [JSONObject] {
    let cases: [(String, [UInt8], String)] = [
        ("truncated-15-bytes", Array(rawHeader().prefix(15)), "truncated"),
        ("version-2", rawHeader(ver: 2), "unsupportedVersion"),
        ("unknown-type", rawHeader(type: 0x99), "unknownPacketType"),
        ("frag-idx-equals-cnt", rawHeader(idx: 3, cntRaw: 3), "invalidFragment"),
        ("frag-idx-over-cnt", rawHeader(idx: 9, cntRaw: 3), "invalidFragment"),
        ("frag-cnt-zero", rawHeader(cntRaw: 0), "invalidFragment"),
        ("frag-cnt-zero-with-key-bit", rawHeader(cntRaw: 0x8000), "invalidFragment"),
        ("frag-cnt-2049", rawHeader(cntRaw: 2049), "fragmentCountTooLarge"),
        ("payload-1201", rawHeader() + [UInt8](repeating: 0, count: 1201), "payloadTooLarge"),
    ]
    return cases.map { name, bytes, error in
        expectError(name, error) { _ = try MediaPacket.decode(bytes) }
        return ["name": name, "hex": hex(bytes), "error": error]
    }
}

private func nackVectors() -> [JSONObject] {
    let cases: [(String, [NackEntry])] = [
        ("single-fragment", [NackEntry(frameNo: 9, fragIdx: 2)]),
        ("whole-frame-and-fragments", [NackEntry(frameNo: 10, fragIdx: NackEntry.wholeFrame), NackEntry(frameNo: 11, fragIdx: 0), NackEntry(frameNo: 11, fragIdx: 5)]),
        ("max-64-entries", (0..<64).map { NackEntry(frameNo: UInt32($0), fragIdx: UInt16($0 % 7)) }),
    ]
    return cases.map { name, entries -> JSONObject in
        let payload: [UInt8]
        do { payload = try NackPayload.encode(entries) } catch { fail("nack \(name): \(error)") }
        return [
            "name": name, "payloadHex": hex(payload),
            "entries": entries.map { ["frameNo": Int($0.frameNo), "fragIdx": Int($0.fragIdx)] },
        ]
    }
}

private func invalidNack() -> [JSONObject] {
    let cases: [(String, [UInt8], String)] = [
        ("count-zero", [0x00], "invalidNackCount"),
        ("count-65", [65] + [UInt8](repeating: 0, count: 65 * 6), "invalidNackCount"),
        ("body-too-short", [0x02, 0, 0, 0, 1, 0, 0], "truncated"),
        ("empty", [], "truncated"),
    ]
    return cases.map { name, bytes, error in
        expectError(name, error) { _ = try NackPayload.decode(bytes) }
        return ["name": name, "payloadHex": hex(bytes), "error": error]
    }
}

private func packetizerVectors() -> [JSONObject] {
    let cases: [(String, Int, Int, Bool)] = [("40-bytes-by-16", 40, 16, true), ("exact-multiple-32-by-16", 32, 16, false), ("single-small", 5, 16, false)]
    return cases.map { name, length, maxPayload, key -> JSONObject in
        let frame = (0..<length).map { UInt8($0 % 251) }
        let packetizer = Packetizer(streamId: 3, maxPayload: maxPayload)
        let packets: [MediaPacket]
        do { packets = try packetizer.packetize(frame: frame, frameNo: 42, ptsMs: 5000, isKeyframe: key) } catch { fail("packetize \(name): \(error)") }
        return [
            "name": name, "streamId": 3, "maxPayload": maxPayload, "frameNo": 42, "ptsMs": 5000, "keyframe": key,
            "frameHex": hex(frame), "packetsHex": packets.map { hex(encode($0)) },
        ]
    }
}
