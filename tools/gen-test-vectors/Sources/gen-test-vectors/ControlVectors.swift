import Foundation
import XdeskWire

func controlVectors() -> JSONObject {
    let messages: [(String, UInt32, ControlMessage)] = [
        ("hello", 1, .hello(Hello(ver: "1.0", caps: 0b0100_0011, name: "Mac của Hào"))),
        ("welcome", 1, .welcome(Welcome(ver: "1.0", sessionId: "s-7f3a", caps: 3))),
        ("reject-version", 2, .reject(Reject(reason: Reject.reasonVersion, detail: "major 2 not supported"))),
        ("display-config", 3, .displayConfig(DisplayConfig(w: 2560, h: 1440, scale: 2.0, fps: 60, codec: .h264))),
        ("display-ready", 3, .displayReady(DisplayReady(udpPort: 52000, streamId: 1))),
        ("keyframe-request", 4, .keyframeRequest(KeyframeRequest(streamId: 1))),
        ("net-report", 5, .netReport(NetReport(rttMs: 12, lossPermille: 25, jitterMs: 3, recvKbps: 18000))),
        ("bitrate-set", 6, .bitrateSet(BitrateSet(kbps: 12000))),
        ("clip-offer", 7, .clipOffer(ClipOffer(kind: .text, size: 42))),
        ("clip-pull", 8, .clipPull(ClipPull(kind: .image))),
        ("control-state", 9, .controlState(ControlState(owner: .agent))),
        ("ping", 10, .ping(Ping(t0: 1_700_000_000_123))),
        ("pong", 10, .pong(Pong(t0: 1_700_000_000_123, t1: 1_700_000_000_130, t2: 1_700_000_000_131))),
        ("bye", 11, .bye(Bye(reason: "user"))),
        ("bye-no-reason", 12, .bye(Bye())),
        ("input-text-vietnamese", 13, .inputText(InputText(text: "Xin chào, Việt Nam"))),
        ("unknown-type", 14, .unknown(type: "future.thing")),
    ]
    let frames: [(String, ControlFrameKind, [UInt8])] = [
        ("handshake-3-bytes", .handshake, [0xAA, 0xBB, 0xCC]),
        ("bulk-1-byte", .bulk, [0x00]),
        ("media-over-tcp-empty", .mediaOverTcp, []),
    ]
    return [
        "version": 1,
        "frames": frames.map { name, kind, payload -> JSONObject in
            let bytes = encodeFrame(ControlFrame(kind: kind, payload: payload))
            return ["name": name, "kind": Int(kind.rawValue), "payloadHex": hex(payload), "hex": hex(bytes)]
        },
        "messages": messages.map { name, id, message -> JSONObject in
            let json = encodeJSON(ControlEnvelope(id: id, message: message))
            let frame = encodeFrame(ControlFrame(kind: .control, payload: Array(json.utf8)))
            return ["name": name, "id": Int(id), "type": message.typeName, "json": json, "frameHex": hex(frame)]
        },
        "invalidFrames": invalidFrames(),
        "incompleteFrames": [
            ["name": "only-3-header-bytes", "hex": "000000"],
            ["name": "payload-missing", "hex": "0000000a02aabb"],
        ] as [JSONObject],
        "invalidMessages": invalidMessages(),
    ]
}

private func encodeFrame(_ frame: ControlFrame) -> [UInt8] {
    do { return try ControlFrameCodec.encode(frame) } catch { fail("encode frame: \(error)") }
}

private func encodeJSON(_ envelope: ControlEnvelope) -> String {
    do { return String(decoding: try ControlMessageCodec.encode(envelope), as: UTF8.self) } catch { fail("encode json: \(error)") }
}

private func invalidFrames() -> [JSONObject] {
    let cases: [(String, String, String)] = [
        ("len-zero", "0000000002", "invalidFrameLength"),
        ("len-over-1MiB", "0010000102", "frameTooLarge"),
        ("len-4GiB-1", "ffffffff02", "frameTooLarge"),
        ("unknown-kind", "0000000109", "unknownFrameKind"),
        ("kind-zero", "0000000100", "unknownFrameKind"),
    ]
    return cases.map { name, h, error in
        expectError(name, error) { _ = try ControlFrameCodec.decode(WireHex.decode(h) ?? []) }
        return ["name": name, "hex": h, "error": error]
    }
}

private func invalidMessages() -> [JSONObject] {
    let cases: [(String, String, String)] = [
        ("not-json", "{{{", "malformedJSON"),
        ("missing-t", "{\"id\":1}", "malformedJSON"),
        ("missing-id", "{\"t\":\"bye\"}", "malformedJSON"),
        ("hello-missing-fields", "{\"id\":1,\"t\":\"hello\"}", "malformedJSON"),
        ("display-config-zero-width", "{\"codec\":\"h264\",\"fps\":60,\"h\":100,\"id\":1,\"scale\":1,\"t\":\"display.config\",\"w\":0}", "invalidField"),
        ("display-config-bad-codec", "{\"codec\":\"vp9\",\"fps\":60,\"h\":100,\"id\":1,\"scale\":1,\"t\":\"display.config\",\"w\":100}", "malformedJSON"),
        ("display-ready-port-zero", "{\"id\":1,\"streamId\":1,\"t\":\"display.ready\",\"udpPort\":0}", "invalidField"),
        ("net-report-loss-over-1000", "{\"id\":1,\"jitterMs\":0,\"lossPermille\":1001,\"recvKbps\":0,\"rttMs\":0,\"t\":\"net.report\"}", "invalidField"),
    ]
    return cases.map { name, json, error in
        expectError(name, error) { _ = try ControlMessageCodec.decode(Array(json.utf8)) }
        return ["name": name, "json": json, "error": error]
    }
}
