/// Một mục NACK: mảnh `fragIdx` của `frameNo`; `fragIdx == wholeFrame` = chưa nhận được mảnh nào của frame.
public struct NackEntry: Sendable, Equatable, Hashable {
    public static let wholeFrame: UInt16 = 0xFFFF
    public static let maxEntries = 64
    static let entrySize = 6

    public var frameNo: UInt32
    public var fragIdx: UInt16

    public init(frameNo: UInt32, fragIdx: UInt16) {
        self.frameNo = frameNo
        self.fragIdx = fragIdx
    }
}

/// Payload gói `nack`: `u8 count (1…64) | count × (u32 frameNo | u16 fragIdx)`.
public enum NackPayload {
    public static func encode(_ entries: [NackEntry]) throws -> [UInt8] {
        guard (1...NackEntry.maxEntries).contains(entries.count) else { throw WireError.invalidNackCount(entries.count) }
        var w = ByteWriter(capacity: 1 + entries.count * NackEntry.entrySize)
        w.u8(UInt8(entries.count))
        for e in entries {
            w.u32(e.frameNo)
            w.u16(e.fragIdx)
        }
        return w.bytes
    }

    public static func decode(_ payload: [UInt8]) throws -> [NackEntry] {
        var r = ByteReader(payload)
        let count = Int(try r.u8())
        guard (1...NackEntry.maxEntries).contains(count) else { throw WireError.invalidNackCount(count) }
        guard r.remaining == count * NackEntry.entrySize else {
            throw WireError.truncated(need: count * NackEntry.entrySize, have: r.remaining)
        }
        var entries: [NackEntry] = []
        for _ in 0..<count {
            entries.append(NackEntry(frameNo: try r.u32(), fragIdx: try r.u16()))
        }
        return entries
    }
}

extension MediaPacket {
    /// Gói NACK hoàn chỉnh (header `fragIdx=0, fragCnt=1`).
    public static func nack(streamId: UInt16, entries: [NackEntry]) throws -> MediaPacket {
        MediaPacket(header: MediaHeader(type: .nack, streamId: streamId, frameNo: 0), payload: try NackPayload.encode(entries))
    }
}
