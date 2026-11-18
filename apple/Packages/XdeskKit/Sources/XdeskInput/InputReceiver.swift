import XdeskWire

/// Phía nhận của kênh input: trả sự kiện cần tin cậy đúng thứ tự seq (đệm sự kiện đến sớm, bỏ trùng),
/// sự kiện không tin cậy đi ngay. `ackSeq` = seq lớn nhất nhận liên tục.
/// Khoảng trống tồn tại quá `gapTimeoutMs` (người gửi đã bỏ cuộc) bị bỏ qua để không kẹt vĩnh viễn.
public struct InputReceiver: Sendable {
    public static let maxAhead = 128
    public static let gapTimeoutMs: Int64 = 500

    private var expected: UInt32 = 1
    private var ahead: [UInt32: InputEvent] = [:]
    private var gapSinceMs: Int64?

    public init() {}

    public var ackSeq: UInt32 { expected - 1 }

    public mutating func accept(_ events: [InputEvent], nowMs: Int64) -> [InputEvent] {
        var ready: [InputEvent] = []
        for event in events {
            guard event.isReliable else { ready.append(event); continue }
            if event.seq == expected {
                ready.append(event)
                expected &+= 1
                drainAhead(into: &ready)
            } else if event.seq > expected, ahead.count < Self.maxAhead {
                ahead[event.seq] = event
            }
        }
        if let since = gapSinceMs, nowMs - since >= Self.gapTimeoutMs, let first = ahead.keys.min() {
            expected = first
            drainAhead(into: &ready)
            gapSinceMs = nil
        }
        if ahead.isEmpty { gapSinceMs = nil } else if gapSinceMs == nil { gapSinceMs = nowMs }
        return ready
    }

    private mutating func drainAhead(into ready: inout [InputEvent]) {
        while let next = ahead.removeValue(forKey: expected) {
            ready.append(next)
            expected &+= 1
        }
    }
}

/// Giới hạn tốc độ sự kiện (token bucket): `capacity` sự kiện, nạp lại `ratePerSecond`/giây.
public struct InputRateLimiter: Sendable {
    public static let defaultRatePerSecond = 1000.0

    private let rate: Double
    private var tokens: Double
    private var lastMs: Int64?

    public init(ratePerSecond: Double = defaultRatePerSecond) {
        rate = ratePerSecond
        tokens = ratePerSecond
    }

    /// Số sự kiện (từ đầu lô) được phép xử lý.
    public mutating func take(_ count: Int, nowMs: Int64) -> Int {
        if let lastMs { tokens = min(rate, tokens + Double(max(0, nowMs - lastMs)) * rate / 1000) }
        lastMs = nowMs
        let allowed = min(count, Int(tokens))
        tokens -= Double(allowed)
        return allowed
    }
}
