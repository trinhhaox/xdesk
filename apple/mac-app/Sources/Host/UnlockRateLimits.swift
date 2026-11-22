import Foundation

/// Giới hạn tần suất mở khoá theo khoá tĩnh của thiết bị (không theo phiên) nên ngắt/kết nối lại không làm mới hạn mức.
/// `HostController` giữ một bản duy nhất và chia sẻ cho mọi `HostSession`.
final class UnlockRateLimits: @unchecked Sendable {
    enum Kind: String, Sendable { case challenge, signed, key }

    private let lock = NSLock()
    private var buckets: [String: RemoteUnlockRateLimiter] = [:]

    func allow(_ kind: Kind, deviceKey: [UInt8]?, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        let id = kind.rawValue + ":" + (deviceKey.map { $0.map { String(format: "%02x", $0) }.joined() } ?? "none")
        return lock.withLock {
            var limiter = buckets[id] ?? Self.makeLimiter(kind)
            let allowed = limiter.allowAttempt(now: now)
            buckets[id] = limiter
            return allowed
        }
    }

    /// Thử thách và chữ ký: 3 lần/60 s. `unlock.key` hợp lệ chỉ gửi vài lần mỗi phiên nên nới 10 lần/60 s.
    private static func makeLimiter(_ kind: Kind) -> RemoteUnlockRateLimiter {
        kind == .key ? RemoteUnlockRateLimiter(maxAttempts: 10, windowSeconds: 60) : RemoteUnlockRateLimiter()
    }
}
