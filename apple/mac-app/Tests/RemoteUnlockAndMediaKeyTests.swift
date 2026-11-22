import Foundation
import Testing
import XdeskWire
@testable import Xdesk

@Suite struct RemoteUnlockAndMediaKeyTests {
    @Test func unlockPolicyRequiresBothGlobalAndDeviceOptIn() {
        #expect(!RemoteUnlockPolicy.canUnlock(globalEnabled: false, deviceAllowed: false))
        #expect(!RemoteUnlockPolicy.canUnlock(globalEnabled: false, deviceAllowed: true))
        #expect(!RemoteUnlockPolicy.canUnlock(globalEnabled: true, deviceAllowed: false))
        #expect(RemoteUnlockPolicy.canUnlock(globalEnabled: true, deviceAllowed: true))
    }

    @Test func rateLimiterCapsThreeAttemptsPerMinute() {
        var limiter = RemoteUnlockRateLimiter(maxAttempts: 3, windowSeconds: 60)
        let a1 = limiter.allowAttempt(now: 100)
        let a2 = limiter.allowAttempt(now: 110)
        let a3 = limiter.allowAttempt(now: 120)
        let a4 = limiter.allowAttempt(now: 130)
        let a5 = limiter.allowAttempt(now: 161)
        #expect(a1)
        #expect(a2)
        #expect(a3)
        #expect(!a4)
        #expect(a5)
    }

    @Test func keychainStoreSavesReadsAndDeletesPasswordBytes() throws {
        let store = RemoteUnlockKeychain(service: "vn.xox.xdesk.tests.unlock.\(UUID().uuidString)", account: "test-user")
        defer { try? store.delete() }

        #expect(!store.hasPassword())
        try store.save(password: "Secr3t-Test!")
        #expect(store.hasPassword())

        let readBack = try store.withPasswordBytes { String(decoding: $0, as: UTF8.self) }
        #expect(readBack == "Secr3t-Test!")

        try store.delete()
        #expect(!store.hasPassword())
    }

    @Test func mediaKeysMapToExpectedNxKeyTypes() {
        #expect(MediaKeyInjector.nxKeyType(for: .volumeUp) == 0)
        #expect(MediaKeyInjector.nxKeyType(for: .volumeDown) == 1)
        #expect(MediaKeyInjector.nxKeyType(for: .mute) == 7)
        #expect(MediaKeyInjector.nxKeyType(for: .playPause) == 16)
        #expect(MediaKeyInjector.nxKeyType(for: .next) == 17)
        #expect(MediaKeyInjector.nxKeyType(for: .previous) == 18)
    }
}
