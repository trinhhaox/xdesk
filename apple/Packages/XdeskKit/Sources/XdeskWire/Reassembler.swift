public struct AssembledFrame: Sendable, Equatable {
    public let streamId: UInt16
    public let frameNo: UInt32
    public let ptsMs: UInt32
    public let isKeyframe: Bool
    public let data: [UInt8]
}

/// Frame đang ghép dở: các mảnh còn thiếu để gửi NACK.
public struct PendingFrame: Sendable, Equatable {
    public let frameNo: UInt32
    public let missing: [UInt16]
    public let firstSeenMs: Int
    public let isKeyframe: Bool
}

/// Ghép mảnh theo `frameNo`. Chịu mất gói, đảo thứ tự và trùng lặp. Thời gian do người gọi truyền vào
/// (`nowMs`) nên kết quả xác định. `frameNo` coi như không quay vòng trong một phiên (u32 ≈ 2 năm ở 60 fps).
public struct Reassembler: Sendable {
    /// Số frame tối đa nằm giữa watermark và frame mới nhất; vượt → bỏ frame cũ nhất.
    public static let window: UInt32 = 256

    private struct Partial {
        var parts: [[UInt8]?]
        var received = 0
        var bytes = 0
        let isKeyframe: Bool
        let ptsMs: UInt32
        let firstSeenMs: Int
    }

    private var partials: [UInt32: Partial] = [:]
    /// Frame ≥ watermark đã hoàn tất hoặc đã bỏ (để chặn gói trùng đến muộn).
    private var finished: Set<UInt32> = []
    private var highest: UInt32?
    private var pendingBytes = 0
    private let maxPendingBytes: Int

    /// Mọi frame < watermark đã xong (hoặc bị bỏ); gói thuộc chúng bị bỏ qua.
    public private(set) var watermark: UInt32
    public private(set) var abandonedCount = 0

    public init(firstFrameNo: UInt32 = 0, maxPendingBytes: Int = 32 << 20) {
        self.watermark = firstFrameNo
        self.maxPendingBytes = maxPendingBytes
    }

    /// Frame nằm dưới frame mới nhất nhưng chưa nhận được mảnh nào.
    public var gaps: [UInt32] {
        guard let top = highest, top > watermark else { return [] }
        return (watermark..<top).filter { partials[$0] == nil && !finished.contains($0) }
    }

    public var pending: [PendingFrame] {
        partials.keys.sorted().compactMap { frameNo in
            guard let p = partials[frameNo] else { return nil }
            let missing = p.parts.indices.filter { p.parts[$0] == nil }.map { UInt16($0) }
            return PendingFrame(frameNo: frameNo, missing: missing, firstSeenMs: p.firstSeenMs, isKeyframe: p.isKeyframe)
        }
    }

    /// Nhận một gói; trả frame khi vừa đủ mảnh. Gói trùng/cũ → `nil`; gói sai → ném lỗi.
    public mutating func ingest(_ packet: MediaPacket, nowMs: Int) throws -> AssembledFrame? {
        let h = packet.header
        guard h.type == .video || h.type == .audio else { throw WireError.unexpectedPacketType(h.type.rawValue) }
        try h.validate()
        guard !packet.payload.isEmpty else { throw WireError.emptyPayload }
        guard packet.payload.count <= MediaPacket.maxPayload else { throw WireError.payloadTooLarge(packet.payload.count) }
        guard h.frameNo >= watermark, !finished.contains(h.frameNo) else { return nil }

        var partial = partials[h.frameNo] ?? Partial(
            parts: Array(repeating: nil, count: Int(h.fragCnt)),
            isKeyframe: h.isKeyframe, ptsMs: h.ptsMs, firstSeenMs: nowMs
        )
        guard partial.parts.count == Int(h.fragCnt) else { throw WireError.inconsistentFragmentCount(frameNo: h.frameNo) }
        highest = max(highest ?? h.frameNo, h.frameNo)
        guard partial.parts[Int(h.fragIdx)] == nil else { return nil }

        partial.parts[Int(h.fragIdx)] = packet.payload
        partial.received += 1
        partial.bytes += packet.payload.count
        pendingBytes += packet.payload.count

        if partial.received == partial.parts.count {
            partials[h.frameNo] = nil
            pendingBytes -= partial.bytes
            markFinished(h.frameNo)
            enforceLimits()
            return AssembledFrame(
                streamId: h.streamId, frameNo: h.frameNo, ptsMs: partial.ptsMs, isKeyframe: partial.isKeyframe,
                data: partial.parts.flatMap { $0 ?? [] }
            )
        }
        partials[h.frameNo] = partial
        enforceLimits()
        return nil
    }

    /// Bỏ một frame (quá hạn): coi như đã xong để watermark tiến lên.
    public mutating func abandon(_ frameNo: UInt32) {
        guard frameNo >= watermark, !finished.contains(frameNo) else { return }
        if let p = partials.removeValue(forKey: frameNo) { pendingBytes -= p.bytes }
        abandonedCount += 1
        markFinished(frameNo)
    }

    /// Bỏ mọi frame < `frameNo` một lần (tầng trên đã bỏ qua chúng); chi phí theo số frame đang giữ.
    public mutating func abandon(before frameNo: UInt32) {
        if frameNo > watermark { advanceWatermark(to: frameNo) }
    }

    /// Nhảy watermark một lần, chi phí theo số frame đang giữ chứ không theo khoảng cách: một gói
    /// có `frameNo` rất lớn (hỏng hoặc cố ý) không được làm treo bộ ghép.
    private mutating func advanceWatermark(to newWatermark: UInt32) {
        let dropped = partials.keys.filter { $0 < newWatermark }
        for frameNo in dropped {
            if let p = partials.removeValue(forKey: frameNo) { pendingBytes -= p.bytes }
        }
        abandonedCount += Int(newWatermark - watermark) - finished.filter { $0 < newWatermark }.count
        finished = finished.filter { $0 >= newWatermark }
        watermark = newWatermark
        while finished.remove(watermark) != nil { watermark &+= 1 }
    }

    private mutating func markFinished(_ frameNo: UInt32) {
        finished.insert(frameNo)
        while finished.remove(watermark) != nil { watermark &+= 1 }
    }

    private mutating func enforceLimits() {
        if let top = highest, top >= watermark, top - watermark >= Self.window {
            advanceWatermark(to: top - Self.window + 1)
        }
        while pendingBytes > maxPendingBytes, let oldest = partials.keys.min() { abandon(oldest) }
    }
}
