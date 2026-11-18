import XdeskWire

/// Các gói đã gửi gần đây để gửi lại theo NACK. Giới hạn theo số frame (khớp cửa sổ bộ ghép) và tổng byte.
struct MediaSendHistory: Sendable {
    private var frames: [UInt32: [MediaPacket]] = [:]
    private var order: [UInt32] = []
    private var totalBytes = 0
    private let maxFrames: Int
    private let maxBytes: Int

    init(maxFrames: Int = Int(Reassembler.window), maxBytes: Int = 16 << 20) {
        self.maxFrames = maxFrames
        self.maxBytes = maxBytes
    }

    var frameCount: Int { order.count }

    mutating func store(frameNo: UInt32, packets: [MediaPacket]) {
        if let old = frames.removeValue(forKey: frameNo) {
            totalBytes -= old.reduce(0) { $0 + $1.payload.count }
            order.removeAll { $0 == frameNo }
        }
        frames[frameNo] = packets
        order.append(frameNo)
        totalBytes += packets.reduce(0) { $0 + $1.payload.count }
        while order.count > maxFrames || (totalBytes > maxBytes && order.count > 1) {
            let oldest = order.removeFirst()
            if let dropped = frames.removeValue(forKey: oldest) { totalBytes -= dropped.reduce(0) { $0 + $1.payload.count } }
        }
    }

    /// Gói cần gửi lại cho một mục NACK; `wholeFrame` = mọi mảnh. Frame đã bị đẩy khỏi lịch sử → rỗng.
    func packets(for entry: NackEntry) -> [MediaPacket] {
        guard let packets = frames[entry.frameNo] else { return [] }
        if entry.fragIdx == NackEntry.wholeFrame { return packets }
        return packets.indices.contains(Int(entry.fragIdx)) ? [packets[Int(entry.fragIdx)]] : []
    }
}
