import Foundation
import Testing
@testable import Xdesk

@Suite struct AppLanguageChoiceTests {
    @Test func mapsChoiceToAppleLanguages() {
        #expect(AppLanguageChoice.system.appleLanguages == nil)
        #expect(AppLanguageChoice.vietnamese.appleLanguages == ["vi"])
        #expect(AppLanguageChoice.english.appleLanguages == ["en"])
    }

    @Test func infersChoiceFromStoredLanguages() {
        #expect(AppLanguageChoice(appleLanguages: nil) == .system)
        #expect(AppLanguageChoice(appleLanguages: []) == .system)
        #expect(AppLanguageChoice(appleLanguages: ["vi"]) == .vietnamese)
        #expect(AppLanguageChoice(appleLanguages: ["vi-VN", "en"]) == .vietnamese)
        #expect(AppLanguageChoice(appleLanguages: ["en-US"]) == .english)
        #expect(AppLanguageChoice(appleLanguages: ["fr"]) == .system)
    }

    @Test func savesAndClearsOverrideInDefaults() throws {
        let suite = "xdesk.tests.language.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        AppLanguageChoice.english.save(to: defaults)
        #expect(AppLanguageChoice.stored(in: defaults, bundleIdentifier: suite) == .english)
        AppLanguageChoice.vietnamese.save(to: defaults)
        #expect(AppLanguageChoice.stored(in: defaults, bundleIdentifier: suite) == .vietnamese)
        AppLanguageChoice.system.save(to: defaults)
        #expect(AppLanguageChoice.stored(in: defaults, bundleIdentifier: suite) == .system)
        // `object(forKey:)` còn đọc cả miền toàn cục/đối số (ngôn ngữ hệ thống) nên kiểm tra thẳng miền riêng của app.
        #expect(defaults.persistentDomain(forName: suite)?[AppLanguageChoice.defaultsKey] == nil)
    }
}
