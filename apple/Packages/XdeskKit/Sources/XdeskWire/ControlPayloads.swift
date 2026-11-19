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
    /// Host thu hồi thiết bị đang kết nối; gửi trên kênh đã mã hoá ngay trước khi đóng.
    public static let reasonRevoked = "revoked"
    public var reason: String
    public var detail: String?
    public init(reason: String, detail: String? = nil) { self.reason = reason; self.detail = detail }
}

/// Cách host dùng màn hình viewer: mở rộng (màn hình mới bên cạnh) hoặc bản sao màn hình Mac theo kích thước viewer.
public enum ScreenMode: String, Codable, Sendable, CaseIterable {
    case extend
    case mirror
}

/// Chỉ có nghĩa khi `mode == .mirror`. `native`: host không đụng màn hình Mac, stream màn hình chính ở độ phân giải thật.
/// `fitDevice`: desktop Mac theo kích thước/chiều xoay viewer. `touch`: như `fitDevice` nhưng độ phân giải logic thấp
/// (viewer tính trong `w`,`h`,`scale`) để nút bấm macOS đủ to cho ngón tay.
public enum MirrorFit: String, Codable, Sendable, CaseIterable {
    case native
    case fitDevice
    case touch
}

public struct DisplayConfig: Codable, Sendable, Equatable {
    public var w: UInt32
    public var h: UInt32
    public var scale: Double
    public var fps: UInt32
    public var codec: VideoCodec
    /// Vắng mặt = `extend` (tương thích viewer cũ).
    public var mode: ScreenMode?
    /// Vắng mặt = `fitDevice` (tương thích viewer/host cũ, vốn bỏ qua khoá lạ).
    public var mirrorFit: MirrorFit?
    public init(w: UInt32, h: UInt32, scale: Double, fps: UInt32, codec: VideoCodec, mode: ScreenMode? = nil, mirrorFit: MirrorFit? = nil) {
        self.w = w; self.h = h; self.scale = scale; self.fps = fps; self.codec = codec; self.mode = mode; self.mirrorFit = mirrorFit
    }

    public var screenMode: ScreenMode { mode ?? .extend }
    public var fit: MirrorFit { mirrorFit ?? .fitDevice }
    /// Chỉ `mirror + native` mới giữ nguyên màn hình Mac và stream màn hình chính.
    public var isNativeMirror: Bool { screenMode == .mirror && fit == .native }
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

/// Giới hạn clipboard: văn bản (UTF-8) và ảnh PNG đều ≤ 10 MiB.
public enum ClipLimits {
    public static let maxBytes = 10 * 1024 * 1024
    /// SHA-256 dạng hex thường (64 ký tự).
    static func isValidHash(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
    }
}

/// "Tôi có clipboard mới": chỉ siêu dữ liệu; bên kia `clip.pull` khi cần. `hash` = SHA-256 hex của dữ liệu (chống lặp/kiểm tra toàn vẹn).
public struct ClipOffer: Codable, Sendable, Equatable {
    public var kind: ClipKind
    public var size: UInt32
    public var hash: String?
    public init(kind: ClipKind, size: UInt32, hash: String? = nil) { self.kind = kind; self.size = size; self.hash = hash }
}

/// Phần đầu của một lần truyền clipboard (trả lời `clip.pull`): ngay sau message này là `ceil(size/65536)` frame bulk liên tiếp.
public struct ClipData: Codable, Sendable, Equatable {
    public var kind: ClipKind
    public var size: UInt32
    public var hash: String
    public init(kind: ClipKind, size: UInt32, hash: String) { self.kind = kind; self.size = size; self.hash = hash }
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

/// Đồng bộ epoch khoá UDP khi hai bên lệch quá cửa sổ nhìn trước (xem `crypto-handshake.md` §8).
/// `epoch` = epoch gửi UDP hiện tại của người gửi message; `ask` = true: "hãy báo epoch gửi của bạn".
public struct RekeyResync: Codable, Sendable, Equatable {
    public var epoch: UInt32
    public var ask: Bool
    public init(epoch: UInt32, ask: Bool) { self.epoch = epoch; self.ask = ask }
}

/// Kết quả ghép đôi (host → viewer) sau message 3 của XX/XXpsk3: host đã duyệt hay từ chối.
public struct PairResult: Codable, Sendable, Equatable {
    public var accepted: Bool
    public init(accepted: Bool) { self.accepted = accepted }
}

/// Xin duyệt quyền điều khiển cho agent AI, hai chiều trên cùng một type (`agent.approve`).
/// Yêu cầu (host → viewer): `requestId`, `agentName`, `summary`, `expiresAt` (ms Unix) và KHÔNG có `allow`.
/// Trả lời (viewer → host): `requestId`, `allow`. Viewer cũ không biết type này sẽ bỏ qua (`.unknown`).
public struct AgentApprove: Codable, Sendable, Equatable {
    public static let maxIdBytes = 64
    public static let maxNameBytes = 128
    public static let maxSummaryBytes = 512

    public var requestId: String
    public var agentName: String?
    public var summary: String?
    public var expiresAt: Int64?
    public var allow: Bool?

    public init(requestId: String, agentName: String? = nil, summary: String? = nil, expiresAt: Int64? = nil, allow: Bool? = nil) {
        self.requestId = requestId; self.agentName = agentName; self.summary = summary; self.expiresAt = expiresAt; self.allow = allow
    }

    public static func request(requestId: String, agentName: String, summary: String, expiresAt: Int64) -> AgentApprove {
        AgentApprove(requestId: requestId, agentName: agentName, summary: summary, expiresAt: expiresAt)
    }

    public static func response(requestId: String, allow: Bool) -> AgentApprove { AgentApprove(requestId: requestId, allow: allow) }

    /// `allow` vắng = đây là yêu cầu duyệt.
    public var isRequest: Bool { allow == nil }

    func validate() throws {
        guard !requestId.isEmpty, requestId.utf8.count <= Self.maxIdBytes else { throw WireError.invalidField("agent.approve.requestId") }
        guard (agentName?.utf8.count ?? 0) <= Self.maxNameBytes else { throw WireError.invalidField("agent.approve.agentName") }
        guard (summary?.utf8.count ?? 0) <= Self.maxSummaryBytes else { throw WireError.invalidField("agent.approve.summary") }
    }
}
