import Foundation
import XdeskWire

func inputVectors() -> JSONObject {
    let events: [(String, InputEvent)] = [
        ("move-center", InputEvent(kind: .move, seq: 1, x: 0.5, y: 0.5)),
        ("left-down", InputEvent(kind: .down, button: 1, mods: 0x0008, seq: 2, x: 0.25, y: 0.75)),
        ("left-up", InputEvent(kind: .up, button: 1, seq: 3, x: 0.25, y: 0.75)),
        ("scroll-vertical", InputEvent(kind: .scroll, seq: 4, dx: 0, dy: -3.5)),
        ("key-a-with-shift", InputEvent(kind: .key, mods: 0x0001, seq: 5, keyUsage: 0x0004)),
        ("text-ref", InputEvent(kind: .textRef, seq: 6)),
        ("touch-corner", InputEvent(kind: .touch, button: 2, seq: 4_294_967_295, x: 1.0, y: 0.0)),
    ]
    let encoded = events.map { name, event in (name, event, encode(event)) }
    return [
        "version": 1,
        "eventSize": InputEvent.size,
        "events": encoded.map { name, e, bytes -> JSONObject in
            [
                "name": name, "kind": Int(e.kind.rawValue), "button": Int(e.button), "mods": Int(e.mods), "seq": Int(e.seq),
                "x": e.x, "y": e.y, "dx": e.dx, "dy": e.dy, "keyUsage": Int(e.keyUsage), "hex": hex(bytes),
            ]
        },
        "batches": [
            ["name": "three-events", "payloadHex": hex(encoded.prefix(3).flatMap { $0.2 }), "count": 3] as JSONObject,
        ],
        "acks": [["name": "ack-258", "seq": 258, "hex": hex(InputAck(seq: 258).encode())] as JSONObject],
        "invalid": invalid(valid: encoded[0].2),
    ]
}

private func encode(_ e: InputEvent) -> [UInt8] {
    do { return try InputEvent.encodeBatch([e]) } catch { fail("encode input: \(error)") }
}

private func invalid(valid: [UInt8]) -> [JSONObject] {
    func patched(_ index: Int, _ bytes: [UInt8]) -> [UInt8] {
        var copy = valid
        copy.replaceSubrange(index..<index + bytes.count, with: bytes)
        return copy
    }
    let cases: [(String, [UInt8], String)] = [
        ("empty-payload", [], "invalidInput"),
        ("length-27", Array(valid.dropLast()), "invalidInput"),
        ("unknown-kind-9", patched(0, [9]), "invalidInput"),
        ("nan-x", patched(8, [0x7F, 0xC0, 0x00, 0x00]), "invalidInput"),
        ("infinity-dy", patched(20, [0x7F, 0x80, 0x00, 0x00]), "invalidInput"),
        ("move-x-above-1", patched(8, [0x3F, 0x80, 0x00, 0x01]), "invalidInput"),
        ("move-y-negative", patched(12, [0xBF, 0x00, 0x00, 0x00]), "invalidInput"),
        ("batch-43-events", Array((0..<43).flatMap { _ in valid }), "invalidInput"),
    ]
    return cases.map { name, bytes, error in
        expectError(name, error) { _ = try InputEvent.decodeBatch(bytes) }
        return ["name": name, "payloadHex": hex(bytes), "error": error]
    }
}
