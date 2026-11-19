import Foundation
import Testing
@testable import Xdesk

@Suite struct UpdateSettingsLogicTests {
    @Test func gentleReminderLetsSparklePresentOnlyInImmediateFocus() {
        #expect(UpdateReminderPolicy.sparkleShouldPresent(inImmediateFocus: true))
        #expect(!UpdateReminderPolicy.sparkleShouldPresent(inImmediateFocus: false))
    }

    @Test func versionLineShowsVersionAndBuild() {
        #expect(UpdateSettingsText.versionLine(shortVersion: "0.1.0-beta", build: "16") == "Phiên bản 0.1.0-beta (bản dựng 16)")
        #expect(UpdateSettingsText.versionLine(shortVersion: nil, build: nil) == "Phiên bản ? (bản dựng ?)")
    }

    @Test func lastCheckLineHandlesNeverAndFuture() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(UpdateSettingsText.lastCheckLine(nil, now: now) == "Chưa kiểm tra lần nào")
        let past = UpdateSettingsText.lastCheckLine(now.addingTimeInterval(-3600), now: now)
        #expect(past.hasPrefix("Lần kiểm tra gần nhất: "))
        #expect(UpdateSettingsText.lastCheckLine(now.addingTimeInterval(86_400), now: now) == UpdateSettingsText.lastCheckLine(now, now: now))
    }
}
