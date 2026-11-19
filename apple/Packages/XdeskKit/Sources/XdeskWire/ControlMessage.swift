/// Message điều khiển có kiểu; `t` trên wire là tên type. Type lạ → `.unknown` (tương thích tiến).
public enum ControlMessage: Sendable, Equatable {
    case hello(Hello)
    case welcome(Welcome)
    case reject(Reject)
    case displayConfig(DisplayConfig)
    case displayReady(DisplayReady)
    case keyframeRequest(KeyframeRequest)
    case netReport(NetReport)
    case bitrateSet(BitrateSet)
    case clipOffer(ClipOffer)
    case clipPull(ClipPull)
    case controlState(ControlState)
    case ping(Ping)
    case pong(Pong)
    case bye(Bye)
    case inputText(InputText)
    case rekey
    case rekeyResync(RekeyResync)
    case pairResult(PairResult)
    case agentApprove(AgentApprove)
    case unknown(type: String)

    /// Giá trị trường `t` trên wire.
    public var typeName: String { wire.type }

    /// Giá trị trường `t` và payload tương ứng.
    var wire: (type: String, payload: (any Encodable)?) {
        switch self {
        case .hello(let p): ("hello", p)
        case .welcome(let p): ("welcome", p)
        case .reject(let p): ("reject", p)
        case .displayConfig(let p): ("display.config", p)
        case .displayReady(let p): ("display.ready", p)
        case .keyframeRequest(let p): ("keyframe.request", p)
        case .netReport(let p): ("net.report", p)
        case .bitrateSet(let p): ("bitrate.set", p)
        case .clipOffer(let p): ("clip.offer", p)
        case .clipPull(let p): ("clip.pull", p)
        case .controlState(let p): ("control.state", p)
        case .ping(let p): ("ping", p)
        case .pong(let p): ("pong", p)
        case .bye(let p): ("bye", p)
        case .inputText(let p): ("input.text", p)
        case .rekey: ("rekey", nil)
        case .rekeyResync(let p): ("rekey.resync", p)
        case .pairResult(let p): ("pair.result", p)
        case .agentApprove(let p): ("agent.approve", p)
        case .unknown(let type): (type, nil)
        }
    }

    /// Kiểm tra giới hạn giá trị (kích thước màn hình, cổng, độ dài text...).
    func validate() throws {
        switch self {
        case .displayConfig(let c):
            guard (1...16384).contains(c.w), (1...16384).contains(c.h) else { throw WireError.invalidField("display.config.size") }
            guard (1...240).contains(c.fps) else { throw WireError.invalidField("display.config.fps") }
            guard c.scale.isFinite, c.scale > 0, c.scale <= 8 else { throw WireError.invalidField("display.config.scale") }
        case .displayReady(let r):
            guard r.udpPort != 0 else { throw WireError.invalidField("display.ready.udpPort") }
        case .inputText(let t):
            guard t.text.utf8.count <= InputText.maxBytes else { throw WireError.invalidField("input.text.text") }
        case .netReport(let n):
            guard n.lossPermille <= 1000 else { throw WireError.invalidField("net.report.lossPermille") }
        case .agentApprove(let a):
            try a.validate()
        default:
            break
        }
    }
}

/// Message kèm `id` (u32) để ghép yêu cầu/phản hồi.
public struct ControlEnvelope: Sendable, Equatable {
    public var id: UInt32
    public var message: ControlMessage

    public init(id: UInt32, message: ControlMessage) {
        self.id = id
        self.message = message
    }
}
