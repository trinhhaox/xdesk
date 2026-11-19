/// Cổng thứ tự frame đặt sau `Reassembler`: nhả frame cho decoder theo `frameNo` tăng dần.
/// Frame hoàn tất đúng thứ tự → nhả ngay (không thêm trễ). Frame đến trước khi frame đứng trước nó xong → giữ tối đa
/// `holdBoundMs`. Hết hạn → bỏ frame thiếu: keyframe đã đủ thì nhảy tới đó (IDR không phụ thuộc gì phía trước);
/// không thì bỏ P-frame, nhả phần đang giữ và đòi keyframe. Nếu frame bỏ là IDR (đã thấy mảnh của nó) thì mọi P-frame
/// sau đó bị loại tới khi có keyframe mới. Thời gian do người gọi truyền (`nowMs`); chi phí theo số frame đang giữ
/// chứ không theo khoảng cách `frameNo`.
public struct FrameOrderGate: Sendable {
    /// Thời gian giữ frame đã đủ để chờ frame đứng trước (≈ 1 RTT; NACK lần đầu sau 20 ms).
    public static let holdBoundMs = 50
    /// Số frame đang giữ tối đa; vượt → coi như hết hạn ngay.
    public static let maxHeld = 32

    public struct Output: Sendable, Equatable {
        /// Frame nhả cho decoder, theo thứ tự.
        public var frames: [AssembledFrame] = []
        /// Mọi frame < giá trị này đã bị bỏ: người gọi báo cho `Reassembler` (`abandon(before:)`).
        public var skipTo: UInt32?
        /// Cần `keyframe.request` (đã bỏ frame hoặc đang loại P-frame chờ IDR).
        public var keyframeNeeded = false
    }

    private struct Held {
        let frame: AssembledFrame
        let arrivedMs: Int
    }

    private var held: [UInt32: Held] = [:]
    private var awaitingKeyframe = false
    /// Frame kế tiếp được phép nhả.
    public private(set) var nextFrameNo: UInt32
    public private(set) var skippedGapCount = 0
    public private(set) var droppedDependentCount = 0

    public init(firstFrameNo: UInt32 = 0) { nextFrameNo = firstFrameNo }

    public var isHolding: Bool { !held.isEmpty }

    public mutating func push(_ frame: AssembledFrame, nowMs: Int) -> Output {
        var out = Output()
        guard frame.frameNo >= nextFrameNo, held[frame.frameNo] == nil else { return out }
        if frame.isKeyframe, frame.frameNo > nextFrameNo {
            held = held.filter { $0.key > frame.frameNo }
            skip(to: frame.frameNo, into: &out)
            awaitingKeyframe = false
        }
        if frame.frameNo == nextFrameNo {
            release(frame, into: &out)
            drain(into: &out)
            return out
        }
        held[frame.frameNo] = Held(frame: frame, arrivedMs: nowMs)
        if held.count > Self.maxHeld { giveUp(&out, pendingKeyframes: []) }
        return out
    }

    /// Gọi định kỳ: hết hạn chờ → bỏ frame thiếu. `pendingKeyframes` = frame đang ghép dở đã biết là keyframe.
    public mutating func poll(nowMs: Int, pendingKeyframes: Set<UInt32>) -> Output {
        var out = Output()
        while let oldest = held.values.map(\.arrivedMs).min(), nowMs - oldest >= Self.holdBoundMs {
            giveUp(&out, pendingKeyframes: pendingKeyframes)
        }
        return out
    }

    private mutating func giveUp(_ out: inout Output, pendingKeyframes: Set<UInt32>) {
        guard let lowest = held.keys.min() else { return }
        if pendingKeyframes.contains(where: { $0 >= nextFrameNo && $0 < lowest }) { awaitingKeyframe = true }
        skip(to: lowest, into: &out)
        out.keyframeNeeded = true
        drain(into: &out)
    }

    private mutating func skip(to frameNo: UInt32, into out: inout Output) {
        skippedGapCount += 1
        nextFrameNo = frameNo
        out.skipTo = frameNo
    }

    private mutating func drain(into out: inout Output) {
        while let next = held.removeValue(forKey: nextFrameNo) { release(next.frame, into: &out) }
    }

    private mutating func release(_ frame: AssembledFrame, into out: inout Output) {
        nextFrameNo = frame.frameNo &+ 1
        if frame.isKeyframe { awaitingKeyframe = false }
        if awaitingKeyframe {
            droppedDependentCount += 1
            out.keyframeNeeded = true
        } else {
            out.frames.append(frame)
        }
    }
}
