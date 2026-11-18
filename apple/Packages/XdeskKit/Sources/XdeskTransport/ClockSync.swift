import Foundation
import XdeskWire

/// Một mẫu ping/pong 4 mốc (ms). `t0` viewer gửi, `t1` host nhận, `t2` host gửi, `t3` viewer nhận.
public struct ClockSample: Sendable, Equatable {
    public let t0: Int64, t1: Int64, t2: Int64, t3: Int64

    public init(t0: Int64, t1: Int64, t2: Int64, t3: Int64) {
        self.t0 = t0; self.t1 = t1; self.t2 = t2; self.t3 = t3
    }

    public init(pong: Pong, receivedAtMs t3: Int64) { self.init(t0: pong.t0, t1: pong.t1, t2: pong.t2, t3: t3) }

    /// Độ lệch đồng hồ host − viewer.
    public var offsetMs: Double { (Double(t1 - t0) + Double(t2 - t3)) / 2 }
    /// RTT mạng, đã trừ thời gian xử lý ở host.
    public var rttMs: Int64 { (t3 - t0) - (t2 - t1) }
    /// Mẫu hợp lệ: RTT không âm và host không "gửi trước khi nhận".
    public var isValid: Bool { rttMs >= 0 && t2 >= t1 && t3 >= t0 }
}

/// Ước lượng offset đồng hồ viewer↔host: giữ `windowSize` mẫu gần nhất, dùng mẫu có RTT nhỏ nhất
/// (đường đi đối xứng nhất, sai số ≤ rtt/2). Logic thuần, không đọc đồng hồ.
public struct ClockSync: Sendable {
    public let windowSize: Int
    private var samples: [ClockSample] = []

    public init(windowSize: Int = 8) { self.windowSize = max(1, windowSize) }

    /// Thêm mẫu; mẫu không hợp lệ bị từ chối (`false`).
    @discardableResult
    public mutating func add(_ sample: ClockSample) -> Bool {
        guard sample.isValid else { return false }
        samples.append(sample)
        if samples.count > windowSize { samples.removeFirst(samples.count - windowSize) }
        return true
    }

    public var sampleCount: Int { samples.count }
    private var best: ClockSample? { samples.min { $0.rttMs < $1.rttMs } }

    /// host − viewer (ms); `nil` khi chưa có mẫu.
    public var offsetMs: Double? { best?.offsetMs }
    public var rttMs: Int64? { best?.rttMs }

    public func viewerToHostMs(_ viewerMs: Int64) -> Int64? { offsetMs.map { viewerMs + Int64($0.rounded()) } }
    public func hostToViewerMs(_ hostMs: Int64) -> Int64? { offsetMs.map { hostMs - Int64($0.rounded()) } }

    /// Phía host: dựng pong từ ping.
    public static func makePong(for ping: Ping, receivedAtMs t1: Int64, sentAtMs t2: Int64) -> Pong {
        Pong(t0: ping.t0, t1: t1, t2: t2)
    }

    /// Đồng hồ treo tường (epoch ms) dùng cho ping/pong.
    public static func wallClockMs() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded()) }
}
