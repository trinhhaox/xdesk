/// Payload JSON của các message điều khiển. Tên trường là hợp đồng wire (camelCase).

public enum VideoCodec: String, Codable, Sendable { case h264, hevc }
public enum ControlOwner: String, Codable, Sendable { case agent, human }
public enum ClipKind: String, Codable, Sendable { case text, image }

public struct Hello: Codable, Sendable, Equatable {
    public var ver: String
    public var caps: UInt32
    public var name: String
    public init(ver: String, caps: UInt32, name: String) { self.ver = ver; self.caps = caps; self.name = name }
}

public struct Welcome: Codable, Sendable, Equatable {
    public var ver: String
    public var sessionId: String
    public var caps: UInt32
    public init(ver: String, sessionId: String, caps: UInt32) { self.ver = ver; self.sessionId = sessionId; self.caps = caps }
}

public struct Reject: Codable, Sendable, Equatable {
    public static let reasonVersion = "version"
    public var reason: String
    public var detail: String?
    public init(reason: String, detail: String? = nil) { self.reason = reason; self.detail = detail }
}

/// Cách host dùng màn hình viewer: mở rộng (màn hình mới bên cạnh) hoặc bản sao màn hình Mac theo kích thước viewer.
public enum ScreenMode: String, Codable, Sendable, CaseIterable {
    case extend
    case mirror
}

public struct DisplayConfig: Codable, Sendable, Equatable {
    public var w: UInt32
    public var h: UInt32
    public var scale: Double
    public var fps: UInt32
    public var codec: VideoCodec
    /// Vắng mặt = `extend` (tương thích viewer cũ).
    public var mode: ScreenMode?
    public init(w: UInt32, h: UInt32, scale: Double, fps: UInt32, codec: VideoCodec, mode: ScreenMode? = nil) {
        self.w = w; self.h = h; self.scale = scale; self.fps = fps; self.codec = codec; self.mode = mode
    }

    public var screenMode: ScreenMode { mode ?? .extend }
}

public struct DisplayReady: Codable, Sendable, Equatable {
    public var udpPort: UInt16
    public var streamId: UInt16
    public init(udpPort: UInt16, streamId: UInt16) { self.udpPort = udpPort; self.streamId = streamId }
}

public struct KeyframeRequest: Codable, Sendable, Equatable {
    public var streamId: UInt16
    public init(streamId: UInt16) { self.streamId = streamId }
}

public struct NetReport: Codable, Sendable, Equatable {
    public var rttMs: UInt32
    public var lossPermille: UInt32
    public var jitterMs: UInt32
    public var recvKbps: UInt32
    public init(rttMs: UInt32, lossPermille: UInt32, jitterMs: UInt32, recvKbps: UInt32) {
        self.rttMs = rttMs; self.lossPermille = lossPermille; self.jitterMs = jitterMs; self.recvKbps = recvKbps
    }
}

public struct BitrateSet: Codable, Sendable, Equatable {
    public var kbps: UInt32
    public init(kbps: UInt32) { self.kbps = kbps }
}

public struct ClipOffer: Codable, Sendable, Equatable {
    public var kind: ClipKind
    public var size: UInt32
    public init(kind: ClipKind, size: UInt32) { self.kind = kind; self.size = size }
}

public struct ClipPull: Codable, Sendable, Equatable {
    public var kind: ClipKind
    public init(kind: ClipKind) { self.kind = kind }
}

public struct ControlState: Codable, Sendable, Equatable {
    public var owner: ControlOwner
    public init(owner: ControlOwner) { self.owner = owner }
}

/// Đồng bộ đồng hồ kiểu NTP: viewer gửi `t0`; host trả `t0,t1,t2`; viewer tự ghi `t3`.
public struct Ping: Codable, Sendable, Equatable {
    public var t0: Int64
    public init(t0: Int64) { self.t0 = t0 }
}

public struct Pong: Codable, Sendable, Equatable {
    public var t0: Int64
    public var t1: Int64
    public var t2: Int64
    public init(t0: Int64, t1: Int64, t2: Int64) { self.t0 = t0; self.t1 = t1; self.t2 = t2 }
}

public struct Bye: Codable, Sendable, Equatable {
    public var reason: String?
    public init(reason: String? = nil) { self.reason = reason }
}

public struct InputText: Codable, Sendable, Equatable {
    public static let maxBytes = 4096
    public var text: String
    public init(text: String) { self.text = text }
}
