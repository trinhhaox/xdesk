public enum MediaPacketType: UInt8, Sendable, CaseIterable {
    case video = 0x10
    /// Để dành (YAGNI ở v1): nhận được thì giải mã được nhưng chưa có ngữ nghĩa.
    case videoParity = 0x11
    case audio = 0x20
    case input = 0x30
    case inputAck = 0x31
    case nack = 0x40
    /// Viewer báo địa chỉ UDP cho host: header + (tuỳ chọn) u64 nonce.
    case probe = 0x50
}

/// Header UDP 16 byte: `u8 ver | u8 ptype | u16 streamId | u32 frameNo | u16 fragIdx | u16 fragCnt | u32 ptsMs`.
/// Bit cao (0x8000) của trường `fragCnt` trên wire là cờ keyframe.
public struct MediaHeader: Sendable, Equatable {
    public static let size = 16
    public static let maxFragmentCount: UInt16 = 2048
    public static let keyframeBit: UInt16 = 0x8000

    public var type: MediaPacketType
    public var streamId: UInt16
    public var frameNo: UInt32
    public var fragIdx: UInt16
    public var fragCnt: UInt16
    public var isKeyframe: Bool
    public var ptsMs: UInt32

    public init(
        type: MediaPacketType, streamId: UInt16, frameNo: UInt32, fragIdx: UInt16 = 0,
        fragCnt: UInt16 = 1, isKeyframe: Bool = false, ptsMs: UInt32 = 0
    ) {
        self.type = type
        self.streamId = streamId
        self.frameNo = frameNo
        self.fragIdx = fragIdx
        self.fragCnt = fragCnt
        self.isKeyframe = isKeyframe
        self.ptsMs = ptsMs
    }

    func validate() throws {
        guard fragCnt <= Self.maxFragmentCount else { throw WireError.fragmentCountTooLarge(fragCnt) }
        guard fragCnt >= 1, fragIdx < fragCnt else { throw WireError.invalidFragment(idx: fragIdx, cnt: fragCnt) }
    }

    func write(to w: inout ByteWriter) throws {
        try validate()
        w.u8(ProtocolVersion.current.major)
        w.u8(type.rawValue)
        w.u16(streamId)
        w.u32(frameNo)
        w.u16(fragIdx)
        w.u16(fragCnt | (isKeyframe ? Self.keyframeBit : 0))
        w.u32(ptsMs)
    }

    static func read(from r: inout ByteReader) throws -> MediaHeader {
        let ver = try r.u8()
        guard ver == ProtocolVersion.current.major else { throw WireError.unsupportedVersion(ver) }
        let rawType = try r.u8()
        guard let type = MediaPacketType(rawValue: rawType) else { throw WireError.unknownPacketType(rawType) }
        let streamId = try r.u16()
        let frameNo = try r.u32()
        let fragIdx = try r.u16()
        let rawCnt = try r.u16()
        let ptsMs = try r.u32()
        let header = MediaHeader(
            type: type, streamId: streamId, frameNo: frameNo, fragIdx: fragIdx,
            fragCnt: rawCnt & ~Self.keyframeBit, isKeyframe: rawCnt & Self.keyframeBit != 0, ptsMs: ptsMs
        )
        try header.validate()
        return header
    }
}

/// Gói UDP: header + payload (≤ 1192 byte; mã hoá xong ≤ 1232 B, vừa MTU IPv6 tối thiểu).
public struct MediaPacket: Sendable, Equatable {
    public static let maxPayload = 1192

    public var header: MediaHeader
    public var payload: [UInt8]

    public init(header: MediaHeader, payload: [UInt8]) {
        self.header = header
        self.payload = payload
    }

    public func encode() throws -> [UInt8] {
        guard payload.count <= Self.maxPayload else { throw WireError.payloadTooLarge(payload.count) }
        var w = ByteWriter(capacity: MediaHeader.size + payload.count)
        try header.write(to: &w)
        w.append(payload)
        return w.bytes
    }

    public static func decode(_ bytes: [UInt8]) throws -> MediaPacket {
        var r = ByteReader(bytes)
        let header = try MediaHeader.read(from: &r)
        guard r.remaining <= maxPayload else { throw WireError.payloadTooLarge(r.remaining) }
        return MediaPacket(header: header, payload: try r.take(r.remaining))
    }
}
