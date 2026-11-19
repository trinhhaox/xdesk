/// Codec của gói audio (byte đầu payload của ptype 0x20).
public enum AudioWireCodec: UInt8, Sendable, Equatable, CaseIterable {
    /// s16 little-endian xen kẽ L,R.
    case pcm = 0
    /// Một access unit AAC-ELD thô (512 mẫu/kênh).
    case aacEld = 1

    /// Cờ thương lượng tương ứng trong `caps`.
    public var capability: Capabilities { self == .pcm ? .audioPCM : .audioAACELD }
}

/// Payload gói audio: `u8 codec | u16 holdMs (BE) | data` (xem `media-packets.md`, mục Âm thanh).
public struct AudioPayload: Sendable, Equatable {
    public static let sampleRate = 48_000
    public static let channels = 2
    public static let bytesPerFrame = 4
    /// Mẫu/kênh trong một gói PCM do host gửi (5 ms).
    public static let pcmFramesPerPacket = 240
    /// Mẫu/kênh trong một access unit AAC-ELD.
    public static let aacFramesPerUnit = 512
    /// AudioSpecificConfig của AAC-ELD 48 kHz stereo không SBR, khung 512.
    public static let aacEldConfig: [UInt8] = [0xF8, 0xE6, 0x40, 0x00]
    static let headerSize = 3
    static let maxDataSize = MediaPacket.maxPayload - headerSize
    /// Access unit AAC-ELD lớn hơn ngần này byte là sai (bộ mã hoá tối đa ~1,5 KB nhưng gói bị chặn ở `maxDataSize`).
    public static let maxUnitBytes = maxDataSize

    public var codec: AudioWireCodec
    /// Host giữ đoạn này bao lâu từ lúc ghi tới lúc gửi (ms, kẹp 0…65535).
    public var holdMs: UInt16
    public var data: [UInt8]

    public init(codec: AudioWireCodec, holdMs: UInt16 = 0, data: [UInt8]) {
        self.codec = codec
        self.holdMs = holdMs
        self.data = data
    }

    public func encode() throws -> [UInt8] {
        try validate()
        var w = ByteWriter(capacity: Self.headerSize + data.count)
        w.u8(codec.rawValue)
        w.u16(holdMs)
        w.append(data)
        return w.bytes
    }

    public static func decode(_ bytes: [UInt8]) throws -> AudioPayload {
        var r = ByteReader(bytes)
        let rawCodec = try r.u8()
        guard let codec = AudioWireCodec(rawValue: rawCodec) else { throw WireError.invalidField("audio.codec") }
        let hold = try r.u16()
        let payload = AudioPayload(codec: codec, holdMs: hold, data: try r.take(r.remaining))
        try payload.validate()
        return payload
    }

    /// Số mẫu/kênh của gói (PCM: theo độ dài; AAC-ELD: cố định 512).
    public var frameCount: Int { codec == .pcm ? data.count / Self.bytesPerFrame : Self.aacFramesPerUnit }

    func validate() throws {
        guard !data.isEmpty else { throw WireError.emptyPayload }
        guard data.count <= Self.maxDataSize else { throw WireError.payloadTooLarge(data.count) }
        if codec == .pcm, data.count % Self.bytesPerFrame != 0 { throw WireError.invalidField("audio.pcm.length") }
    }

    /// Gói media ptype 0x20 không phân mảnh.
    public func mediaPacket(streamId: UInt16, sequence: UInt32, ptsMs: UInt32) throws -> MediaPacket {
        MediaPacket(
            header: MediaHeader(type: .audio, streamId: streamId, frameNo: sequence, ptsMs: ptsMs),
            payload: try encode()
        )
    }
}
