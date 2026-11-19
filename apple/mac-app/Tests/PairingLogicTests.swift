import Foundation
import Testing
import XdeskCrypto
@testable import Xdesk

@Suite struct PairingLogicTests {
    @Test func qrOnlyReadyWhenEncryptedListeningAndNobodyWatching() {
        #expect(PairingAvailability.evaluate(encrypted: true, port: 47800, activeViewers: 0) == .ready(port: 47800))
        #expect(PairingAvailability.evaluate(encrypted: true, port: 47800, activeViewers: 2) == .sessionActive(viewers: 2))
        #expect(PairingAvailability.evaluate(encrypted: true, port: nil, activeViewers: 0) == .hostStopped)
        #expect(PairingAvailability.evaluate(encrypted: false, port: 47800, activeViewers: 0) == .plaintextMode)
    }

    @Test func everyBlockedStateExplainsItselfAndReadyDoesNot() {
        #expect(PairingAvailability.ready(port: 1).blockedMessage == nil)
        for state in [PairingAvailability.hostStopped, .plaintextMode, .sessionActive(viewers: 1)] {
            #expect(state.blockedMessage?.isEmpty == false)
        }
    }

    @Test func approvalDefaultsAreViewPlusInputAndViewIsAlwaysOn() {
        let draft = ApprovalDraft()
        #expect(draft.permissions == DevicePermissions(view: true, input: true, clipboard: false, audio: false))
        var all = ApprovalDraft(input: false, clipboard: true, audio: true)
        #expect(all.permissions.view && !all.permissions.input && all.permissions.clipboard && all.permissions.audio)
        all.input = false
        #expect(all.permissions.view)
    }

    @Test func countdownClampsAndFormats() {
        let issued = Date(timeIntervalSince1970: 1000)
        #expect(PairingCountdown.remaining(issuedAt: issued, now: issued, lifetime: 120) == 120)
        #expect(PairingCountdown.remaining(issuedAt: issued, now: issued.addingTimeInterval(59.2), lifetime: 120) == 61)
        #expect(PairingCountdown.remaining(issuedAt: issued, now: issued.addingTimeInterval(500), lifetime: 120) == 0)
        #expect(PairingCountdown.label(seconds: 125) == "2:05")
        #expect(PairingCountdown.label(seconds: 0) == "0:00")
    }

    @Test func qrImageRendersForPairingUri() throws {
        let uri = try PairingURI(hostPublicKey: [UInt8](repeating: 1, count: 32), token: [UInt8](repeating: 2, count: 32), addresses: ["192.168.1.2:47800"])
        let image = try #require(QrImage.make(uri.string, side: 240))
        #expect(image.size.width >= 200)
    }

    @Test func secureRegistryTracksWindowIds() {
        let registry = SecureWindowRegistry()
        registry.insert(42)
        #expect(registry.windowIDs == [42])
        registry.remove(42)
        #expect(registry.windowIDs.isEmpty)
    }
}
