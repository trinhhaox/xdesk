import Foundation
import XdeskWire

private let helloSha256 = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
private let transferId = "7f3a9c01-5b2e-4d11-9a47-0c6e2d8b1f55"

func controlVectors() -> JSONObject {
    let messages: [(String, UInt32, ControlMessage)] = baseMessages + sessionMessages + fileMessages + unlockAttestationMessages + windowControlMessages
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
        "unlockAttestation": unlockAttestationSignatureVector,
    ]
}

private let baseMessages: [(String, UInt32, ControlMessage)] = [
        ("hello", 1, .hello(Hello(ver: "1.0", caps: 0b0100_0011, name: "Mac của Hào"))),
        ("welcome", 1, .welcome(Welcome(ver: "1.0", sessionId: "s-7f3a", caps: 3))),
        ("reject-version", 2, .reject(Reject(reason: Reject.reasonVersion, detail: "major 2 not supported"))),
        ("display-config", 3, .displayConfig(DisplayConfig(w: 2560, h: 1440, scale: 2.0, fps: 60, codec: .h264))),
        ("display-config-mirror-native", 3, .displayConfig(DisplayConfig(w: 2560, h: 1440, scale: 2.0, fps: 60, codec: .h264, mode: .mirror, mirrorFit: .native))),
        ("display-config-mirror-fit-device", 3, .displayConfig(DisplayConfig(w: 1179, h: 2556, scale: 3.0, fps: 60, codec: .h264, mode: .mirror, mirrorFit: .fitDevice))),
        ("display-config-mirror-touch", 3, .displayConfig(DisplayConfig(w: 1080, h: 2342, scale: 2.0, fps: 60, codec: .hevc, mode: .mirror, mirrorFit: .touch))),
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
        ("agent-approve-request", 15, .agentApprove(.request(
            requestId: "req-7f3a", agentName: "Claude", summary: "Mở TextEdit và gõ lời chào", expiresAt: 1_700_000_060_000))),
        ("agent-approve-response-allow", 15, .agentApprove(.response(requestId: "req-7f3a", allow: true))),
        ("agent-approve-response-deny", 16, .agentApprove(.response(requestId: "req-9c01", allow: false))),
        ("clip-offer-with-hash", 7, .clipOffer(ClipOffer(kind: .image, size: 5, hash: helloSha256))),
        ("clip-data", 8, .clipData(ClipData(kind: .text, size: 5, hash: helloSha256))),
        ("rekey", 0, .rekey),
        ("rekey-resync-announce", 17, .rekeyResync(RekeyResync(epoch: 3, ask: false))),
        ("rekey-resync-ask", 18, .rekeyResync(RekeyResync(epoch: 2, ask: true))),
        ("pair-result-accepted", 19, .pairResult(PairResult(accepted: true))),
        ("pair-result-rejected", 19, .pairResult(PairResult(accepted: false))),
    ]

/// Cấu hình hiển thị đổi giữa phiên, chọn màn hình, Chỉ điều khiển, khoá/mở khoá, phím media, agent cần người giúp.
private let sessionMessages: [(String, UInt32, ControlMessage)] = [
    ("display-config-video-paused-display-id", 3, .displayConfig(DisplayConfig(
        w: 1179, h: 2556, scale: 3.0, fps: 60, codec: .h264, mode: .mirror, mirrorFit: .fitDevice, videoPaused: true, displayId: 69_733_632))),
    ("display-reconfigure", 20, .displayReconfigure(DisplayConfig(
        w: 1170, h: 2532, scale: 3.0, fps: 60, codec: .hevc, mode: .mirror, mirrorFit: .touch))),
    ("display-reconfigure-paused-display-id", 21, .displayReconfigure(DisplayConfig(
        w: 2560, h: 1440, scale: 2.0, fps: 30, codec: .h264, mode: .extend, videoPaused: true, displayId: 2))),
    ("display-list", 22, .displayList(DisplayList(displays: [
        DisplayInfo(id: 1, name: "Màn hình Retina tích hợp", width: 3024, height: 1964, isMain: true),
        DisplayInfo(id: 69_733_632, name: "DELL U2723QE", width: 3840, height: 2160, isMain: false),
    ]))),
    ("video-pause", 23, .videoPause(VideoPause(streamId: 1))),
    ("video-resume", 24, .videoResume(VideoResume(streamId: 1))),
    ("system-lock", 25, .systemLock(SystemLock())),
    ("system-unlock", 26, .systemUnlock(SystemUnlock())),
    ("system-unlock-with-token", 27, .systemUnlock(SystemUnlock(token: "t-7f3a"))),
    ("system-unlock-result-ok", 28, .systemUnlockResult(SystemUnlockResult(ok: true, message: "Đã mở khoá màn hình Mac"))),
    ("system-unlock-result-rate-limited", 29, .systemUnlockResult(SystemUnlockResult(
        ok: false, message: "Thử mở khoá quá nhiều lần, vui lòng đợi 1 phút"))),
    ("media-key-play-pause", 30, .mediaKey(MediaKey(key: .playPause))),
    ("media-key-next", 31, .mediaKey(MediaKey(key: .next))),
    ("media-key-previous", 32, .mediaKey(MediaKey(key: .previous))),
    ("media-key-volume-up", 33, .mediaKey(MediaKey(key: .volumeUp))),
    ("media-key-volume-down", 34, .mediaKey(MediaKey(key: .volumeDown))),
    ("media-key-mute", 35, .mediaKey(MediaKey(key: .mute))),
    ("agent-help-request", 36, .agentHelp(.request(requestId: "help-31c2", reason: "Cần nhập mã OTP gửi về điện thoại"))),
    ("agent-help-resolved", 37, .agentHelp(.resolved(requestId: "help-31c2"))),
]

/// Truyền tệp: streaming (`file.start/chunk/done/cancel`, khoá `transferId`) và dạng Base64 cũ (`file.offer/data`).
private let fileMessages: [(String, UInt32, ControlMessage)] = [
    ("file-start", 40, .fileStart(FileStart(id: transferId, name: "ảnh chụp màn hình.png", size: 1_048_576))),
    ("file-start-empty-file", 41, .fileStart(FileStart(id: "t-0", name: "rong.txt", size: 0))),
    ("file-start-max-2gib", 42, .fileStart(FileStart(id: transferId, name: "disk.img", size: FileTransferLimits.maxBytes))),
    ("file-chunk-full", 43, .fileChunk(FileChunk(id: transferId, size: UInt32(FileTransferLimits.chunkBytes)))),
    ("file-chunk-tail", 44, .fileChunk(FileChunk(id: transferId, size: 5))),
    ("file-done", 45, .fileDone(FileDone(id: transferId, hash: helloSha256))),
    ("file-cancel", 46, .fileCancel(FileCancel(id: transferId, reason: "cancelled"))),
    ("file-cancel-no-reason", 47, .fileCancel(FileCancel(id: transferId))),
    ("file-offer-legacy", 48, .fileOffer(FileOffer(name: "báo cáo.pdf", size: 1_048_576, hash: helloSha256))),
    ("file-offer-legacy-empty-hash", 49, .fileOffer(FileOffer(name: "báo cáo.pdf", size: 5))),
    ("file-data-legacy", 50, .fileData(FileData(name: "báo cáo.pdf", chunk: "SGVsbG8=", isLast: true))),
]

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
        ("display-config-bad-mirror-fit", "{\"codec\":\"h264\",\"fps\":60,\"h\":100,\"id\":1,\"mirrorFit\":\"zoom\",\"mode\":\"mirror\",\"scale\":1,\"t\":\"display.config\",\"w\":100}", "malformedJSON"),
        ("display-ready-port-zero", "{\"id\":1,\"streamId\":1,\"t\":\"display.ready\",\"udpPort\":0}", "invalidField"),
        ("net-report-loss-over-1000", "{\"id\":1,\"jitterMs\":0,\"lossPermille\":1001,\"recvKbps\":0,\"rttMs\":0,\"t\":\"net.report\"}", "invalidField"),
        ("agent-approve-empty-request-id", "{\"id\":1,\"requestId\":\"\",\"t\":\"agent.approve\"}", "invalidField"),
    ] + newInvalidMessages + unlockAttestationInvalidMessages + windowControlInvalidMessages

    return cases.map { name, json, error in
        expectError(name, error) { _ = try ControlMessageCodec.decode(Array(json.utf8)) }
        return ["name": name, "json": json, "error": error]
    }
}

/// Giá trị ngoài giới hạn (`invalidField`) và thiếu/sai kiểu trường (`malformedJSON`) của các message phiên/tệp.
private let newInvalidMessages: [(String, String, String)] = [
    ("display-reconfigure-zero-height", "{\"codec\":\"h264\",\"fps\":60,\"h\":0,\"id\":1,\"scale\":1,\"t\":\"display.reconfigure\",\"w\":100}", "invalidField"),
    ("display-list-missing-displays", "{\"id\":1,\"t\":\"display.list\"}", "malformedJSON"),
    ("display-list-item-missing-is-main", "{\"displays\":[{\"height\":1,\"id\":1,\"name\":\"a\",\"width\":1}],\"id\":1,\"t\":\"display.list\"}", "malformedJSON"),
    ("video-pause-missing-stream-id", "{\"id\":1,\"t\":\"video.pause\"}", "malformedJSON"),
    ("media-key-unknown-key", "{\"id\":1,\"key\":\"eject\",\"t\":\"media.key\"}", "malformedJSON"),
    ("system-unlock-result-missing-message", "{\"id\":1,\"ok\":true,\"t\":\"system.unlock.result\"}", "malformedJSON"),
    ("agent-help-missing-request-id", "{\"id\":1,\"reason\":\"x\",\"t\":\"agent.help\"}", "malformedJSON"),
    ("file-start-missing-transfer-id", "{\"id\":1,\"name\":\"a.txt\",\"size\":1,\"t\":\"file.start\"}", "malformedJSON"),
    ("file-start-empty-transfer-id", "{\"id\":1,\"name\":\"a.txt\",\"size\":1,\"t\":\"file.start\",\"transferId\":\"\"}", "invalidField"),
    ("file-start-transfer-id-65-bytes", "{\"id\":1,\"name\":\"a.txt\",\"size\":1,\"t\":\"file.start\",\"transferId\":\"\(String(repeating: "a", count: 65))\"}", "invalidField"),
    ("file-start-empty-name", "{\"id\":1,\"name\":\"\",\"size\":1,\"t\":\"file.start\",\"transferId\":\"t\"}", "invalidField"),
    ("file-start-name-256-bytes", "{\"id\":1,\"name\":\"\(String(repeating: "a", count: 256))\",\"size\":1,\"t\":\"file.start\",\"transferId\":\"t\"}", "invalidField"),
    ("file-start-size-over-2gib", "{\"id\":1,\"name\":\"a.txt\",\"size\":2147483649,\"t\":\"file.start\",\"transferId\":\"t\"}", "invalidField"),
    ("file-chunk-size-zero", "{\"id\":1,\"size\":0,\"t\":\"file.chunk\",\"transferId\":\"t\"}", "invalidField"),
    ("file-chunk-size-over-64kib", "{\"id\":1,\"size\":65537,\"t\":\"file.chunk\",\"transferId\":\"t\"}", "invalidField"),
    ("file-done-uppercase-hash", "{\"hash\":\"\(String(repeating: "A", count: 64))\",\"id\":1,\"t\":\"file.done\",\"transferId\":\"t\"}", "invalidField"),
    ("file-done-short-hash", "{\"hash\":\"abcd\",\"id\":1,\"t\":\"file.done\",\"transferId\":\"t\"}", "invalidField"),
    ("file-cancel-empty-transfer-id", "{\"id\":1,\"t\":\"file.cancel\",\"transferId\":\"\"}", "invalidField"),
    ("file-offer-missing-hash", "{\"id\":1,\"name\":\"a\",\"size\":1,\"t\":\"file.offer\"}", "malformedJSON"),
    ("file-data-missing-is-last", "{\"chunk\":\"AA==\",\"id\":1,\"name\":\"a\",\"t\":\"file.data\"}", "malformedJSON"),
]
