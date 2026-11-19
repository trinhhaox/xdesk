import Foundation
import Testing
@testable import XdeskAgent

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

private func makeGuard(clock: Clock = Clock(), token: String? = "secret-token") -> RequestGuard {
    RequestGuard(port: 47810, token: { token }, now: { clock.now })
}

private func headers(host: String? = "127.0.0.1:47810", auth: String? = "Bearer secret-token", origin: String? = nil) -> [String: String] {
    var result: [String: String] = [:]
    if let host { result["host"] = host }
    if let auth { result["authorization"] = auth }
    if let origin { result["origin"] = origin }
    return result
}

@Suite struct RequestGuardTests {
    @Test func allowsLoopbackHostsWithValidToken() {
        let guardian = makeGuard()
        #expect(guardian.evaluate(headers: headers()) == .allow)
        #expect(guardian.evaluate(headers: headers(host: "localhost:47810")) == .allow)
        #expect(guardian.evaluate(headers: headers(host: "LOCALHOST:47810", auth: "bearer secret-token")) == .allow)
    }

    @Test(arguments: ["evil.com", "evil.com:47810", "127.0.0.1", "127.0.0.1:1234", "localhost", "127.0.0.1.evil.com:47810", "0.0.0.0:47810"])
    func rejectsForeignHost(_ host: String) {
        #expect(makeGuard().evaluate(headers: headers(host: host)) == .reject(status: 403, message: "Host không được phép"))
    }

    @Test func rejectsMissingHost() {
        #expect(makeGuard().evaluate(headers: headers(host: nil)) == .reject(status: 403, message: "Host không được phép"))
    }

    @Test func rejectsAnyOriginEvenWithValidToken() {
        for origin in ["http://evil.com", "http://127.0.0.1:47810", "null"] {
            #expect(makeGuard().evaluate(headers: headers(origin: origin)) == .reject(status: 403, message: "Origin không được phép"))
        }
    }

    @Test func rejectsMissingOrWrongToken() {
        for auth in [nil, "Bearer wrong", "Bearer ", "secret-token", "Basic secret-token", "Bearer secret-token-extra"] {
            let guardian = makeGuard()
            #expect(guardian.evaluate(headers: headers(auth: auth)) == .reject(status: 401, message: "Thiếu hoặc sai Bearer token"))
        }
    }

    @Test func rejectsEverythingWhenNoTokenConfigured() {
        #expect(makeGuard(token: nil).evaluate(headers: headers()) == .reject(status: 401, message: "Thiếu hoặc sai Bearer token"))
    }

    @Test func locksAfterFiveFailuresThenRecovers() {
        let clock = Clock()
        let guardian = makeGuard(clock: clock)
        for _ in 0..<5 { #expect(guardian.evaluate(headers: headers(auth: "Bearer x")) == .reject(status: 401, message: "Thiếu hoặc sai Bearer token")) }
        let locked = guardian.evaluate(headers: headers())
        #expect(locked == .reject(status: 429, message: "Sai token quá nhiều lần, thử lại sau", retryAfterSeconds: 60))
        clock.advance(59)
        if case .reject(let status, _, _) = guardian.evaluate(headers: headers()) { #expect(status == 429) } else { Issue.record("phải còn khoá") }
        clock.advance(2)
        #expect(guardian.evaluate(headers: headers()) == .allow)
    }

    @Test func failuresOutsideWindowDoNotAccumulate() {
        let clock = Clock()
        let guardian = makeGuard(clock: clock)
        for _ in 0..<4 { _ = guardian.evaluate(headers: headers(auth: "Bearer x")) }
        clock.advance(61)
        _ = guardian.evaluate(headers: headers(auth: "Bearer x"))
        #expect(guardian.evaluate(headers: headers()) == .allow)
    }

    @Test func hostAndOriginRejectionsDoNotCountTowardLockout() {
        let guardian = makeGuard()
        for _ in 0..<10 { _ = guardian.evaluate(headers: headers(host: "evil.com")) }
        #expect(guardian.evaluate(headers: headers()) == .allow)
    }

    @Test func constantTimeEqualsMatchesOnlyIdentical() {
        #expect(ConstantTime.equals("abc", "abc"))
        #expect(!ConstantTime.equals("abc", "abd"))
        #expect(!ConstantTime.equals("abc", "abcd"))
        #expect(!ConstantTime.equals("", "a"))
    }
}
