import Foundation

/// JSON phẳng: `{"id":1,"t":"ping","t0":123}`. Khoá sắp xếp để đầu ra xác định (test vectors).
public enum ControlMessageCodec {
    private enum Keys: String, CodingKey { case t, id }

    private struct Head: Decodable {
        let t: String
        let id: UInt32
    }

    private struct Flat: Encodable {
        let type: String
        let id: UInt32
        let payload: (any Encodable)?

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(type, forKey: .t)
            try c.encode(id, forKey: .id)
            // Payload ghi thêm khoá vào cùng container JSON (các struct payload không có khoá `t`/`id`).
            try payload?.encode(to: encoder)
        }
    }

    public static func encode(_ envelope: ControlEnvelope) throws -> [UInt8] {
        try envelope.message.validate()
        let wire = envelope.message.wire
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return Array(try encoder.encode(Flat(type: wire.type, id: envelope.id, payload: wire.payload)))
        } catch {
            throw WireError.malformedJSON("encode: \(error)")
        }
    }

    public static func decode(_ bytes: [UInt8]) throws -> ControlEnvelope {
        let data = Data(bytes)
        let decoder = JSONDecoder()
        do {
            let head = try decoder.decode(Head.self, from: data)
            let message = try decodeMessage(type: head.t, data: data, decoder: decoder)
            try message.validate()
            return ControlEnvelope(id: head.id, message: message)
        } catch let error as WireError {
            throw error
        } catch {
            throw WireError.malformedJSON(String(describing: error))
        }
    }

    private static func decodeMessage(type: String, data: Data, decoder: JSONDecoder) throws -> ControlMessage {
        func body<P: Decodable>(_: P.Type) throws -> P { try decoder.decode(P.self, from: data) }
        switch type {
        case "hello": return .hello(try body(Hello.self))
        case "welcome": return .welcome(try body(Welcome.self))
        case "reject": return .reject(try body(Reject.self))
        case "display.config": return .displayConfig(try body(DisplayConfig.self))
        case "display.ready": return .displayReady(try body(DisplayReady.self))
        case "keyframe.request": return .keyframeRequest(try body(KeyframeRequest.self))
        case "net.report": return .netReport(try body(NetReport.self))
        case "bitrate.set": return .bitrateSet(try body(BitrateSet.self))
        case "clip.offer": return .clipOffer(try body(ClipOffer.self))
        case "clip.pull": return .clipPull(try body(ClipPull.self))
        case "clip.data": return .clipData(try body(ClipData.self))
        case "control.state": return .controlState(try body(ControlState.self))
        case "ping": return .ping(try body(Ping.self))
        case "pong": return .pong(try body(Pong.self))
        case "bye": return .bye(try body(Bye.self))
        case "input.text": return .inputText(try body(InputText.self))
        case "rekey": return .rekey
        case "rekey.resync": return .rekeyResync(try body(RekeyResync.self))
        case "pair.result": return .pairResult(try body(PairResult.self))
        case "agent.approve": return .agentApprove(try body(AgentApprove.self))
        case "system.lock": return .systemLock(try body(SystemLock.self))
        case "system.unlock": return .systemUnlock(try body(SystemUnlock.self))
        case "file.offer": return .fileOffer(try body(FileOffer.self))
        case "file.data": return .fileData(try body(FileData.self))
        case "agent.help": return .agentHelp(try body(AgentHelp.self))
        default: return .unknown(type: type)
        }
    }
}
