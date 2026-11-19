import CryptoKit
import Foundation
import os

public enum GuardDecision: Sendable, Equatable {
    case allow
    case reject(status: Int, message: String, retryAfterSeconds: Int? = nil)
}

/// Cổng bảo vệ endpoint MCP: Host/Origin (chống DNS rebinding), Bearer token (so sánh hằng thời gian) và khoá khi dò token.
public final class RequestGuard: Sendable {
    private struct State {
        var failures: [Date] = []
        var lockedUntil: Date?
    }

    private let port: UInt16
    private let token: @Sendable () -> String?
    private let now: @Sendable () -> Date
    private let maxFailures: Int
    private let window: TimeInterval
    private let lockout: TimeInterval
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(
        port: UInt16,
        token: @escaping @Sendable () -> String?,
        now: @escaping @Sendable () -> Date = { Date() },
        maxFailures: Int = 5,
        window: TimeInterval = 60,
        lockout: TimeInterval = 60
    ) {
        self.port = port
        self.token = token
        self.now = now
        self.maxFailures = maxFailures
        self.window = window
        self.lockout = lockout
    }

    /// Thứ tự: Host → Origin → khoá tạm → token. Host/Origin sai không tính vào bộ đếm dò token.
    public func evaluate(headers: [String: String]) -> GuardDecision {
        guard isAllowedHost(headers["host"]) else { return .reject(status: 403, message: "Host không được phép") }
        // Allowlist Origin rỗng: client MCP dạng CLI không gửi Origin, trình duyệt thì luôn gửi.
        if headers["origin"] != nil { return .reject(status: 403, message: "Origin không được phép") }
        let current = now()
        if let wait = lockRemaining(at: current) {
            return .reject(status: 429, message: "Sai token quá nhiều lần, thử lại sau", retryAfterSeconds: wait)
        }
        if isAuthorized(headers["authorization"]) {
            state.withLock { $0.failures.removeAll() }
            return .allow
        }
        recordFailure(at: current)
        return .reject(status: 401, message: "Thiếu hoặc sai Bearer token")
    }

    private func isAllowedHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "127.0.0.1:\(port)" || host == "localhost:\(port)"
    }

    private func isAuthorized(_ header: String?) -> Bool {
        guard let expected = token(), let header, header.count > 7, header.prefix(7).lowercased() == "bearer " else { return false }
        return ConstantTime.equals(String(header.dropFirst(7)), expected)
    }

    private func lockRemaining(at date: Date) -> Int? {
        state.withLock { state in
            guard let until = state.lockedUntil else { return nil }
            if until <= date { state.lockedUntil = nil; return nil }
            return max(1, Int(until.timeIntervalSince(date).rounded(.up)))
        }
    }

    private func recordFailure(at date: Date) {
        state.withLock { state in
            state.failures = state.failures.filter { date.timeIntervalSince($0) < window } + [date]
            if state.failures.count >= maxFailures {
                state.lockedUntil = date.addingTimeInterval(lockout)
                state.failures.removeAll()
            }
        }
    }
}

enum ConstantTime {
    /// Băm SHA-256 hai vế để độ dài bằng nhau rồi cộng dồn XOR, không thoát sớm.
    static func equals(_ lhs: String, _ rhs: String) -> Bool {
        let (a, b) = (Array(SHA256.hash(data: Data(lhs.utf8))), Array(SHA256.hash(data: Data(rhs.utf8))))
        var difference: UInt8 = 0
        for (x, y) in zip(a, b) { difference |= x ^ y }
        return difference == 0
    }
}
