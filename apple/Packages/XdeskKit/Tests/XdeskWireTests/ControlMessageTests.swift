import Foundation
import Testing
@testable import XdeskWire

@Suite struct ControlMessageTests {
    private func roundTrip(_ message: ControlMessage, id: UInt32 = 5) throws -> ControlEnvelope {
        try ControlMessageCodec.decode(try ControlMessageCodec.encode(ControlEnvelope(id: id, message: message)))
    }

    @Test func roundTripEveryType() throws {
        let all: [ControlMessage] = [
            .hello(Hello(ver: "1.0", caps: 3, name: "x")), .welcome(Welcome(ver: "1.0", sessionId: "s", caps: 1)),
            .reject(Reject(reason: "version")), .displayConfig(DisplayConfig(w: 100, h: 50, scale: 1.5, fps: 30, codec: .hevc)),
            .displayReady(DisplayReady(udpPort: 1, streamId: 2)), .keyframeRequest(KeyframeRequest(streamId: 1)),
            .netReport(NetReport(rttMs: 1, lossPermille: 1000, jitterMs: 2, recvKbps: 3)), .bitrateSet(BitrateSet(kbps: 5)),
            .clipOffer(ClipOffer(kind: .image, size: 9)), .clipPull(ClipPull(kind: .text)),
            .controlState(ControlState(owner: .human)), .ping(Ping(t0: -1)), .pong(Pong(t0: 1, t1: 2, t2: 3)),
            .bye(Bye()), .inputText(InputText(text: "Tiếng Việt: ươ, ă, â, đ 😀")), .unknown(type: "later.feature"),
        ]
        for message in all {
            let env = try roundTrip(message)
            #expect(env == ControlEnvelope(id: 5, message: message))
        }
    }

    @Test func canonicalJSONHasSortedFlatKeys() throws {
        let bytes = try ControlMessageCodec.encode(ControlEnvelope(id: 10, message: .ping(Ping(t0: 123))))
        #expect(String(decoding: bytes, as: UTF8.self) == "{\"id\":10,\"t\":\"ping\",\"t0\":123}")
    }

    @Test func unknownFieldsAreIgnored() throws {
        let json = "{\"extra\":[1,2],\"id\":3,\"t\":\"clip.pull\",\"kind\":\"text\",\"z\":null}"
        #expect(try ControlMessageCodec.decode(Array(json.utf8)).message == .clipPull(ClipPull(kind: .text)))
    }

    @Test func encodeRejectsOutOfRangeValues() {
        let badConfig = DisplayConfig(w: 100, h: 100, scale: .nan, fps: 60, codec: .h264)
        expectWireError("invalidField") { _ = try ControlMessageCodec.encode(.init(id: 1, message: .displayConfig(badConfig))) }
        let bigText = InputText(text: String(repeating: "é", count: InputText.maxBytes))
        expectWireError("invalidField") { _ = try ControlMessageCodec.encode(.init(id: 1, message: .inputText(bigText))) }
        let fps = DisplayConfig(w: 100, h: 100, scale: 1, fps: 241, codec: .h264)
        expectWireError("invalidField") { _ = try ControlMessageCodec.encode(.init(id: 1, message: .displayConfig(fps))) }
    }

    @Test func decodeRejectsMalformedInput() {
        for json in ["", "[]", "null", "{\"t\":5,\"id\":1}", "{\"t\":\"ping\",\"id\":-1,\"t0\":1}", "\u{0}"] {
            expectWireError("malformedJSON") { _ = try ControlMessageCodec.decode(Array(json.utf8)) }
        }
        expectWireError("malformedJSON") { _ = try ControlMessageCodec.decode([0xFF, 0xFE, 0x00]) }
    }

    @Test func vectors() throws {
        let v = try Vectors.load("control-frames.json")
        for c in try v.list("messages") {
            let json = Array(try c.str("json").utf8)
            let env = try ControlMessageCodec.decode(json)
            #expect(env.id == UInt32(try c.int("id")))
            #expect(env.message.typeName == (try c.str("type")))
            #expect(try ControlMessageCodec.encode(env) == json, label(c))
            let frame = try #require(try ControlFrameCodec.decode(try c.bytes("frameHex"))).frame
            #expect(frame.kind == .control)
            #expect(frame.payload == json)
        }
        for c in try v.list("invalidMessages") {
            let json = Array(try c.str("json").utf8)
            expectWireError(try c.str("error")) { _ = try ControlMessageCodec.decode(json) }
        }
    }

    @Test func versionNegotiation() throws {
        let v1 = ProtocolVersion.current
        #expect(v1.string == "1.0")
        #expect(ProtocolVersion(string: "1.7") == ProtocolVersion(major: 1, minor: 7))
        #expect(v1.isCompatible(with: ProtocolVersion(major: 1, minor: 9)))
        #expect(!v1.isCompatible(with: ProtocolVersion(major: 2, minor: 0)))
        for bad in ["", "1", "1.", ".1", "1.2.3", "a.b", "256.0", "-1.0"] { #expect(ProtocolVersion(string: bad) == nil) }
        let common = Capabilities([.h264, .hevc, .clipboard]).intersection([.h264, .audioPCM, .clipboard])
        #expect(common == [.h264, .clipboard])
    }
}
