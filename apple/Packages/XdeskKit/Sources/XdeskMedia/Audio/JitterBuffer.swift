import XdeskWire

/// Bộ đệm chống rung cho audio phía viewer (thuần logic, không phụ thuộc AVFoundation nên test được).
/// Mẫu s16 xen kẽ L,R. Bắt đầu phát khi đủ `targetMs`; thiếu → phát im lặng và đệm lại; dư quá `overflowMs` → bỏ phần cũ
/// về `targetMs` (ưu tiên trễ thấp hơn lip-sync tuyệt đối). Khoảng trống số thứ tự được lấp bằng im lặng.
public struct AudioJitterBuffer: Sendable {
    public static let targetMs = 40
    public static let overflowMs = 100
    /// Khoảng trống lớn hơn ngần này gói coi như dòng bị ngắt: bỏ đệm và bắt đầu lại.
    static let maxConcealedPackets = 50
    private static let channels = AudioPayload.channels
    private static let framesPerMs = AudioPayload.sampleRate / 1000

    public struct Counters: Sendable, Equatable {
        public var packetsAccepted = 0
        public var lateOrDuplicate = 0
        public var concealedFrames = 0
        public var underruns = 0
        public var overflowTrims = 0
        public var resets = 0
    }

    public private(set) var counters = Counters()
    private var samples: [Int16] = []
    private var head = 0
    private var started = false
    private var lastSequence: UInt32?
    private var lastPacketFrames = AudioPayload.pcmFramesPerPacket

    public init() {}

    /// Số mẫu/kênh đang chờ phát.
    public var bufferedFrames: Int { (samples.count - head) / Self.channels }
    public var depthMs: Int { bufferedFrames / Self.framesPerMs }

    /// Nhận một gói đã giải mã. Gói cũ/trùng bị bỏ.
    public mutating func push(sequence: UInt32, pcm: [Int16]) {
        guard !pcm.isEmpty, pcm.count % Self.channels == 0 else { return }
        if let last = lastSequence {
            let gap = Int(Int32(bitPattern: sequence &- last)) - 1
            if gap < 0 { counters.lateOrDuplicate += 1; return }
            if gap > Self.maxConcealedPackets { reset() } else if gap > 0 { conceal(packets: gap) }
        }
        lastSequence = sequence
        lastPacketFrames = pcm.count / Self.channels
        samples.append(contentsOf: pcm)
        counters.packetsAccepted += 1
        trimIfOverflowing()
    }

    /// Lấy đúng `frames` mẫu/kênh cho thiết bị phát; thiếu thì bù im lặng.
    public mutating func pull(frames: Int) -> [Int16] {
        let want = frames * Self.channels
        if !started {
            guard bufferedFrames >= Self.targetMs * Self.framesPerMs else { return [Int16](repeating: 0, count: want) }
            started = true
        }
        let available = min(want, samples.count - head)
        var out = Array(samples[head..<head + available])
        head += available
        if available < want {
            out.append(contentsOf: [Int16](repeating: 0, count: want - available))
            started = false
            counters.underruns += 1
        }
        compactIfNeeded()
        return out
    }

    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        head = 0
        started = false
        lastSequence = nil
        counters.resets += 1
    }

    private mutating func conceal(packets: Int) {
        let frames = packets * lastPacketFrames
        samples.append(contentsOf: [Int16](repeating: 0, count: frames * Self.channels))
        counters.concealedFrames += frames
    }

    private mutating func trimIfOverflowing() {
        guard depthMs > Self.overflowMs else { return }
        let keep = Self.targetMs * Self.framesPerMs * Self.channels
        head = samples.count - keep
        counters.overflowTrims += 1
    }

    private mutating func compactIfNeeded() {
        guard head > 16_384 else { return }
        samples.removeFirst(head)
        head = 0
    }
}
