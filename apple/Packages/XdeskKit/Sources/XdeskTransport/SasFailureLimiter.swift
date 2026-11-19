import Foundation

/// Giới hạn ghép đôi SAS: tối đa `maxFailures` lần hỏng (lệch cam kết, host bấm "Không khớp", bắt tay lỗi) trong `window`.
struct SasFailureLimiter: Sendable {
    static let maxFailures = 3
    static let window: TimeInterval = 600

    private var failures: [Date] = []

    func allows(now: Date = Date()) -> Bool {
        failures.filter { now.timeIntervalSince($0) < Self.window }.count < Self.maxFailures
    }

    mutating func recordFailure(now: Date = Date()) {
        prune(now)
        failures.append(now)
    }

    private mutating func prune(_ now: Date) {
        failures.removeAll { now.timeIntervalSince($0) >= Self.window }
    }
}
