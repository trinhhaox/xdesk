/// Message điều khiển có kiểu; `t` trên wire là tên type. Type lạ → `.unknown` (tương thích tiến).
public enum ControlMessage: Sendable, Equatable {
    case hello(Hello)
    case welcome(Welcome)
    case reject(Reject)
    case displayConfig(DisplayConfig)
    case displayReconfigure(DisplayConfig)
    case displayReady(DisplayReady)
    case keyframeRequest(KeyframeRequest)
    case videoPause(VideoPause)
    case videoResume(VideoResume)
    case netReport(NetReport)
    case bitrateSet(BitrateSet)
    case clipOffer(ClipOffer)
    case clipPull(ClipPull)
    case clipData(ClipData)
    case controlState(ControlState)
    case ping(Ping)
    case pong(Pong)
    case bye(Bye)
    case inputText(InputText)
    case rekey
    case rekeyResync(RekeyResync)
    case pairResult(PairResult)
    case agentApprove(AgentApprove)
    case systemLock(SystemLock)
    case systemUnlock(SystemUnlock)
    case systemUnlockResult(SystemUnlockResult)
    case mediaKey(MediaKey)
    case displayList(DisplayList)
    case fileOffer(FileOffer)
    case fileData(FileData)
    case fileStart(FileStart)
    case fileChunk(FileChunk)
    case fileDone(FileDone)
    case fileCancel(FileCancel)
    case agentHelp(AgentHelp)
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
        case .displayReconfigure(let p): ("display.reconfigure", p)
        case .displayReady(let p): ("display.ready", p)
        case .keyframeRequest(let p): ("keyframe.request", p)
        case .videoPause(let p): ("video.pause", p)
        case .videoResume(let p): ("video.resume", p)
        case .netReport(let p): ("net.report", p)
        case .bitrateSet(let p): ("bitrate.set", p)
        case .clipOffer(let p): ("clip.offer", p)
        case .clipPull(let p): ("clip.pull", p)
        case .clipData(let p): ("clip.data", p)
        case .controlState(let p): ("control.state", p)
        case .ping(let p): ("ping", p)
        case .pong(let p): ("pong", p)
        case .bye(let p): ("bye", p)
        case .inputText(let p): ("input.text", p)
        case .rekey: ("rekey", nil)
        case .rekeyResync(let p): ("rekey.resync", p)
        case .pairResult(let p): ("pair.result", p)
        case .agentApprove(let p): ("agent.approve", p)
        case .systemLock(let p): ("system.lock", p)
        case .systemUnlock(let p): ("system.unlock", p)
        case .systemUnlockResult(let p): ("system.unlock.result", p)
        case .mediaKey(let p): ("media.key", p)
        case .displayList(let p): ("display.list", p)
        case .fileOffer(let p): ("file.offer", p)
        case .fileData(let p): ("file.data", p)
        case .fileStart(let p): ("file.start", p)
        case .fileChunk(let p): ("file.chunk", p)
        case .fileDone(let p): ("file.done", p)
        case .fileCancel(let p): ("file.cancel", p)
        case .agentHelp(let p): ("agent.help", p)
        case .unknown(let type): (type, nil)
        }
    }

    /// Kiểm tra giới hạn giá trị (kích thước màn hình, cổng, độ dài text...).
    func validate() throws {
        switch self {
        case .displayConfig(let c), .displayReconfigure(let c):
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
        case .clipOffer(let o):
            guard o.size > 0, Int(o.size) <= ClipLimits.maxBytes else { throw WireError.invalidField("clip.offer.size") }
            if let hash = o.hash, !ClipLimits.isValidHash(hash) { throw WireError.invalidField("clip.offer.hash") }
        case .clipData(let d):
            guard d.size > 0, Int(d.size) <= ClipLimits.maxBytes else { throw WireError.invalidField("clip.data.size") }
            guard ClipLimits.isValidHash(d.hash) else { throw WireError.invalidField("clip.data.hash") }
        case .fileStart(let s):
            guard !s.id.isEmpty, s.id.utf8.count <= FileTransferLimits.maxIdBytes else { throw WireError.invalidField("file.start.id") }
            guard !s.name.isEmpty, s.name.utf8.count <= FileTransferLimits.maxNameBytes else { throw WireError.invalidField("file.start.name") }
            guard s.size <= FileTransferLimits.maxBytes else { throw WireError.invalidField("file.start.size") }
        case .fileChunk(let c):
            guard !c.id.isEmpty, c.id.utf8.count <= FileTransferLimits.maxIdBytes else { throw WireError.invalidField("file.chunk.id") }
            guard c.size >= 1, Int(c.size) <= FileTransferLimits.chunkBytes else { throw WireError.invalidField("file.chunk.size") }
        case .fileDone(let d):
            guard !d.id.isEmpty, d.id.utf8.count <= FileTransferLimits.maxIdBytes else { throw WireError.invalidField("file.done.id") }
            guard ClipLimits.isValidHash(d.hash) else { throw WireError.invalidField("file.done.hash") }
        case .fileCancel(let c):
            guard !c.id.isEmpty, c.id.utf8.count <= FileTransferLimits.maxIdBytes else { throw WireError.invalidField("file.cancel.id") }
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
