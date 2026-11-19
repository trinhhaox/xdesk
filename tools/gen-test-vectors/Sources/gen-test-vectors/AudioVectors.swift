import Foundation
import XdeskWire

/// `audio-payloads.json`: payload gói audio (ptype 0x20) hợp lệ + gói media đầy đủ, và các payload sai kèm mã lỗi. Bản Kotlin phải khớp từng byte.
func audioVectors() -> JSONObject {
    let valid: [(String, AudioWireCodec, UInt16, [UInt8], UInt16, UInt32, UInt32)] = [
        ("pcm-one-frame", .pcm, 0, [0x01, 0x00, 0xFF, 0xFF], 1, 0, 0),
        ("pcm-5ms-with-hold", .pcm, 258, [UInt8](repeating: 0x7F, count: 8), 3, 9, 5000),
        ("aac-eld-unit-max-hold", .aacEld, 65535, [0x21, 0x1A, 0x04, 0xFF, 0x00], 3, 4_294_967_295, 4_294_967_295),
        ("pcm-max-size", .pcm, 1, [UInt8](repeating: 0x00, count: 1184), 65535, 1, 1),
    ]
    let invalid: [(String, [UInt8], String)] = [
        ("unknown-codec", [0x09, 0, 0, 1, 2, 3, 4], "invalidField"),
        ("empty-data", [0x00, 0, 0], "emptyPayload"),
        ("pcm-length-not-multiple-of-4", [0x00, 0, 0, 1, 2, 3, 4, 5, 6], "invalidField"),
        ("truncated-header", [0x00, 0x01], "truncated"),
        ("empty", [], "truncated"),
        ("data-too-large", [0x01, 0, 0] + [UInt8](repeating: 0, count: 1190), "payloadTooLarge"),
    ]
    return [
        "version": 1,
        "payloads": valid.map { name, codec, hold, data, streamId, sequence, pts -> JSONObject in
            let payload = AudioPayload(codec: codec, holdMs: hold, data: data)
            guard let bytes = try? payload.encode(), let packet = try? payload.mediaPacket(streamId: streamId, sequence: sequence, ptsMs: pts),
                  let wire = try? packet.encode() else { fail("encode audio payload \(name)") }
            return [
                "name": name, "codec": Int(codec.rawValue), "holdMs": Int(hold), "dataHex": hex(data), "hex": hex(bytes),
                "streamId": Int(streamId), "sequence": Int(sequence), "ptsMs": Int(pts), "packetHex": hex(wire),
            ]
        },
        "invalidPayloads": invalid.map { name, bytes, error -> JSONObject in ["name": name, "hex": hex(bytes), "error": error] },
    ]
}
