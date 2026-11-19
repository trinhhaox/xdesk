import XdeskWire

/// Phía host: gom mẫu s16 xen kẽ từ ScreenCaptureKit (kích thước tuỳ ý) thành gói PCM 240 mẫu/kênh hoặc access unit AAC-ELD 512 mẫu.
/// `ptsMs` của mỗi gói tính theo số mẫu đã phát từ mốc neo (chính xác theo mẫu), neo lại khi lệch quá `reanchorMs`
/// (SCK ngừng/đứt đoạn). `holdMs` = thời gian giữ tính từ lúc ghi tới lúc gửi.
public struct AudioPacketizer {
    static let reanchorMs = 20.0
    private static let channels = AudioPayload.channels

    public let streamId: UInt16
    private var sequence: UInt32 = 0
    private var buffer: [Int16] = []
    private var anchorMs = 0.0
    private var emittedFrames = 0
    private var anchored = false
    private var encoder: AacEldEncoder?

    public init(streamId: UInt16) { self.streamId = streamId }

    /// `captureMs`: mốc ghi của mẫu đầu tiên trong `samples`; `nowMs`: giờ hiện tại (cùng đồng hồ video).
    /// Lỗi mã hoá AAC-ELD chỉ làm mất gói đó (log ở nơi gọi qua giá trị trả về rỗng), không dừng dòng.
    public mutating func push(samples: [Int16], captureMs: Double, nowMs: Double, codec: AudioWireCodec) throws -> [MediaPacket] {
        guard samples.count % Self.channels == 0, !samples.isEmpty else { return [] }
        let bufferedFrames = buffer.count / Self.channels
        let expected = anchorMs + Double(emittedFrames + bufferedFrames) * 1000 / Double(AudioPayload.sampleRate)
        if !anchored || abs(captureMs - expected) > Self.reanchorMs {
            buffer.removeAll(keepingCapacity: true)
            anchorMs = captureMs
            emittedFrames = 0
            anchored = true
        }
        buffer.append(contentsOf: samples)
        let unit = codec == .pcm ? AudioPayload.pcmFramesPerPacket : AudioPayload.aacFramesPerUnit
        var packets: [MediaPacket] = []
        while buffer.count / Self.channels >= unit {
            let chunk = Array(buffer.prefix(unit * Self.channels))
            buffer.removeFirst(chunk.count)
            let startMs = anchorMs + Double(emittedFrames) * 1000 / Double(AudioPayload.sampleRate)
            emittedFrames += unit
            guard let packet = try makePacket(chunk, codec: codec, startMs: startMs, nowMs: nowMs) else { continue }
            packets.append(packet)
        }
        return packets
    }

    private mutating func makePacket(_ chunk: [Int16], codec: AudioWireCodec, startMs: Double, nowMs: Double) throws -> MediaPacket? {
        let data: [UInt8]
        switch codec {
        case .pcm:
            data = Self.littleEndianBytes(chunk)
        case .aacEld:
            if encoder == nil { encoder = try AacEldEncoder() }
            guard let unit = try encoder?.encode(chunk) else { return nil }
            data = unit
        }
        let hold = UInt16(clamping: Int(max(0, nowMs - startMs).rounded()))
        let payload = AudioPayload(codec: codec, holdMs: hold, data: data)
        defer { sequence &+= 1 }
        return try payload.mediaPacket(streamId: streamId, sequence: sequence, ptsMs: UInt32(clamping: Int(max(0, startMs).rounded())))
    }

    static func littleEndianBytes(_ samples: [Int16]) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(samples.count * 2)
        for s in samples {
            let u = UInt16(bitPattern: s)
            out.append(UInt8(truncatingIfNeeded: u))
            out.append(UInt8(truncatingIfNeeded: u >> 8))
        }
        return out
    }

    static func samples(fromLittleEndian bytes: [UInt8]) -> [Int16] {
        stride(from: 0, to: bytes.count - 1, by: 2).map { Int16(bitPattern: UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8) }
    }
}
