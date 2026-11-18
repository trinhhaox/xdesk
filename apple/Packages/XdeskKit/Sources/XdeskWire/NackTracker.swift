/// Quyết định khi nào gửi NACK / bỏ frame. Không giữ thời gian thực; người gọi truyền `nowMs`.
public struct NackTracker: Sendable {
    public struct Config: Sendable, Equatable {
        /// Chờ trước khi NACK lần đầu (≈ RTT/2).
        public var nackDelayMs = 20
        /// Khoảng cách tối thiểu giữa hai lần NACK cùng một mảnh.
        public var retryIntervalMs = 40
        /// Quá hạn này (≈ 2×RTT trở lên) → bỏ frame, người gọi nên gửi `keyframe.request`.
        public var giveUpMs = 500
        public init() {}
    }

    public struct Poll: Sendable, Equatable {
        public var nacks: [NackEntry]
        public var abandoned: [UInt32]
    }

    public var config: Config
    private var gapSince: [UInt32: Int] = [:]
    private var lastSent: [NackEntry: Int] = [:]

    public init(config: Config = Config()) { self.config = config }

    public mutating func poll(_ reassembler: inout Reassembler, nowMs: Int) -> Poll {
        var candidates: [(frameNo: UInt32, firstSeenMs: Int, missing: [UInt16])] = []
        for frameNo in reassembler.gaps {
            candidates.append((frameNo, gapSince[frameNo] ?? nowMs, [NackEntry.wholeFrame]))
        }
        for p in reassembler.pending { candidates.append((p.frameNo, p.firstSeenMs, p.missing)) }
        candidates.sort { $0.frameNo < $1.frameNo }

        var result = Poll(nacks: [], abandoned: [])
        for c in candidates {
            gapSince[c.frameNo] = c.firstSeenMs
            let age = nowMs - c.firstSeenMs
            if age >= config.giveUpMs {
                reassembler.abandon(c.frameNo)
                result.abandoned.append(c.frameNo)
                continue
            }
            guard age >= config.nackDelayMs else { continue }
            for idx in c.missing where result.nacks.count < NackEntry.maxEntries {
                let entry = NackEntry(frameNo: c.frameNo, fragIdx: idx)
                if let last = lastSent[entry], nowMs - last < config.retryIntervalMs { continue }
                lastSent[entry] = nowMs
                result.nacks.append(entry)
            }
        }
        let watermark = reassembler.watermark
        gapSince = gapSince.filter { $0.key >= watermark }
        lastSent = lastSent.filter { $0.key.frameNo >= watermark }
        return result
    }
}
