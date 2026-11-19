/// ABR kiểu AIMD, logic thuần (người gọi truyền `nowMs`, không đọc đồng hồ).
/// Giảm ×0.8 khi mất gói > 2% hoặc RTT vượt đường nền > 30%; tăng +5% sau 2 s ổn định. Sàn 2 Mb/s, trần 40 Mb/s (LAN); trần 15 Mb/s khi RTT > 20 ms (Tailscale/4G).
public struct BitrateController: Sendable {
    public struct Limits: Sendable, Equatable {
        public var minKbps = 2_000
        public var maxKbps = 40_000
        public var lossThresholdPermille = 20
        public var rttIncreaseRatio = 1.3
        /// Chênh RTT tuyệt đối tối thiểu để coi là tắc nghẽn (RTT LAN ~1 ms dao động nhiều theo tỉ lệ).
        public var rttMinDeltaMs = 5
        public var decreaseFactor = 0.8
        public var increaseFactor = 1.05
        public var stableMs = 2_000
        /// RTT vượt ngưỡng này (ms) thì áp trần `highRttMaxKbps` (đường dài như Tailscale qua 4G).
        public var highRttThresholdMs = 20
        public var highRttMaxKbps = 15_000
        public init() {}
    }

    public let limits: Limits
    public private(set) var kbps: Int
    private var baselineRttMs: Double?
    /// Lần giảm/tăng gần nhất (hoặc báo cáo đầu tiên) — mốc cho cửa sổ ổn định.
    private var lastEventMs: Int?

    public init(initialKbps: Int, limits: Limits = Limits()) {
        self.limits = limits
        self.kbps = min(max(initialKbps, limits.minKbps), limits.maxKbps)
    }

    /// Nạp một báo cáo mạng (`net.report`); trả bitrate mới nếu đổi.
    public mutating func update(lossPermille: Int, rttMs: Int, nowMs: Int) -> Int? {
        let previous = kbps
        let ceiling = rttMs > limits.highRttThresholdMs ? min(limits.maxKbps, limits.highRttMaxKbps) : limits.maxKbps
        if kbps > ceiling {
            kbps = ceiling
            lastEventMs = nowMs
            return kbps
        }
        if isCongested(lossPermille: lossPermille, rttMs: rttMs) {
            lastEventMs = nowMs
            kbps = max(limits.minKbps, Int(Double(kbps) * limits.decreaseFactor))
        } else {
            trackBaseline(Double(rttMs))
            guard let last = lastEventMs else { lastEventMs = nowMs; return nil }
            guard nowMs - last >= limits.stableMs else { return nil }
            lastEventMs = nowMs
            kbps = min(ceiling, max(kbps + 1, Int(Double(kbps) * limits.increaseFactor)))
        }
        return kbps == previous ? nil : kbps
    }

    private func isCongested(lossPermille: Int, rttMs: Int) -> Bool {
        if lossPermille > limits.lossThresholdPermille { return true }
        guard let base = baselineRttMs else { return false }
        let rtt = Double(rttMs)
        return rtt > base * limits.rttIncreaseRatio && rtt - base >= Double(limits.rttMinDeltaMs)
    }

    /// Đường nền = trung bình trượt của RTT khi không tắc nghẽn (không bị kéo lên bởi lúc nghẽn).
    private mutating func trackBaseline(_ rtt: Double) {
        guard let base = baselineRttMs else { baselineRttMs = rtt; return }
        baselineRttMs = rtt < base ? rtt : base * 0.9 + rtt * 0.1
    }
}
