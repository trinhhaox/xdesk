import Foundation
import Testing
@testable import Xdesk

@Suite struct UpdateSettingsLogicTests {
    @Test func gentleReminderLetsSparklePresentOnlyInImmediateFocus() {
        #expect(UpdateReminderPolicy.sparkleShouldPresent(inImmediateFocus: true))
        #expect(!UpdateReminderPolicy.sparkleShouldPresent(inImmediateFocus: false))
    }

    @Test func versionLineShowsVersionAndBuild() {
        #expect(UpdateSettingsText.versionLine(shortVersion: "0.1.0-beta", build: "16") == String(localized: "Phiên bản 0.1.0-beta (bản dựng 16)"))
        #expect(UpdateSettingsText.versionLine(shortVersion: nil, build: nil) == String(localized: "Phiên bản ? (bản dựng ?)"))
    }

    @Test func lastCheckLineHandlesNeverAndFuture() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(UpdateSettingsText.lastCheckLine(nil, now: now) == String(localized: "Chưa kiểm tra lần nào"))
        let pastDate = now.addingTimeInterval(-3600)
        let formatted = pastDate.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(.autoupdatingCurrent))
        #expect(UpdateSettingsText.lastCheckLine(pastDate, now: now) == String(localized: "Lần kiểm tra gần nhất: \(formatted)"))
        #expect(UpdateSettingsText.lastCheckLine(now.addingTimeInterval(86_400), now: now) == UpdateSettingsText.lastCheckLine(now, now: now))
    }
}
