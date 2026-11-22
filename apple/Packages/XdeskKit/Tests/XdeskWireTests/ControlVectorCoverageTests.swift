import Testing
@testable import XdeskWire

/// Mọi type điều khiển đã biết phải có ít nhất một vector trong `control-frames.json`
/// (thêm type mới vào `ControlMessage` mà quên vector thì test này đỏ).
struct ControlVectorCoverageTests {
    static let knownTypes: Set<String> = [
        "hello", "welcome", "reject", "display.config", "display.reconfigure", "display.ready", "keyframe.request",
        "video.pause", "video.resume", "net.report", "bitrate.set", "clip.offer", "clip.pull", "clip.data",
        "control.state", "ping", "pong", "bye", "input.text", "rekey", "rekey.resync", "pair.result", "agent.approve",
        "system.lock", "system.unlock", "system.unlock.result", "media.key", "display.list", "file.offer", "file.data",
        "file.start", "file.chunk", "file.done", "file.cancel", "agent.help", "system.unlock.challenge", "unlock.key", "system.lock.result",
        "host.state", "window.pick", "window.selected", "window.adjust",
    ]

    @Test func everyKnownTypeHasAVector() throws {
        let v = try Vectors.load("control-frames.json")
        let covered = Set(try v.list("messages").map { try $0.str("type") })
        #expect(Self.knownTypes.subtracting(covered).isEmpty, "thiếu vector cho: \(Self.knownTypes.subtracting(covered).sorted())")
    }

    @Test func vectorTypesAreAllKnown() throws {
        let v = try Vectors.load("control-frames.json")
        for m in try v.list("messages") {
            let type = try m.str("type")
            if type == "future.thing" { continue }
            #expect(Self.knownTypes.contains(type), "type lạ trong vector: \(type)")
        }
    }

    @Test func fileMessagesUseTransferIdKeyNotEnvelopeId() throws {
        let start = try ControlMessageCodec.decode(Array(#"{"id":7,"name":"a.txt","size":3,"t":"file.start","transferId":"abc"}"#.utf8))
        #expect(start.id == 7)
        #expect(start.message == .fileStart(FileStart(id: "abc", name: "a.txt", size: 3)))
    }
}
