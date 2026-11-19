import CryptoKit
import Foundation
import Testing
@testable import XdeskCrypto

@Suite struct PairingHardeningTests {
    @Test func tokenIsInvalidatedAfterFiveFailures() throws {
        var issuer = PairingTokenIssuer()
        let token = try issuer.issue()
        for _ in 0..<(PairingTokenIssuer.maxFailures - 1) {
            let closed = issuer.recordFailure()
            #expect(!closed)
        }
        let stillActive = issuer.activeToken() != nil
        #expect(stillActive)
        let closedNow = issuer.recordFailure()
        let afterClose = issuer.activeToken()
        let consumed = issuer.consume(matching: token.bytes)
        #expect(closedNow)
        #expect(afterClose == nil)
        #expect(!consumed)
    }

    @Test func issuingANewTokenResetsTheFailureCountAndInvalidateClosesIt() throws {
        var issuer = PairingTokenIssuer()
        try issuer.issue()
        for _ in 0..<(PairingTokenIssuer.maxFailures - 1) { issuer.recordFailure() }
        try issuer.issue()
        let closedAfterReset = issuer.recordFailure()
        issuer.invalidate()
        let active = issuer.activeToken()
        let closedWhenIdle = issuer.recordFailure()
        #expect(!closedAfterReset)
        #expect(active == nil)
        #expect(!closedWhenIdle)
    }

    @Test func receiverResyncsToAnEpochBeyondTheLookahead() throws {
        let key = SymmetricKey(size: .bits256)
        var sender = DatagramSender(key: key)
        var receiver = DatagramReceiver(key: key)
        let header = [UInt8](repeating: 1, count: DatagramFormat.headerLength)
        for _ in 0..<7 { try sender.rekey() }
        let datagram = try sender.seal(header: header, payload: [1, 2, 3])
        #expect(throws: CryptoError.unknownEpoch) { _ = try receiver.open(datagram) }
        try receiver.resync(toEpoch: sender.epoch)
        #expect(try receiver.open(datagram).payload == [1, 2, 3])
        #expect(receiver.epoch == 7)
    }

    @Test func resyncIgnoresPastEpochsAndRefusesHugeJumps() throws {
        var receiver = DatagramReceiver(key: SymmetricKey(size: .bits256))
        try receiver.resync(toEpoch: 0)
        #expect(receiver.epoch == 0)
        #expect(throws: CryptoError.unknownEpoch) { try receiver.resync(toEpoch: DatagramReceiver.maxResyncGap + 1) }
        #expect(receiver.epoch == 0)
    }

    @Test func tamperedFileIsMovedAsideBeforeTheNextSaveAndNoticeIsSticky() async throws {
        let storage = InMemoryPairedDevicesStorage()
        let macKey = InMemoryPairedDevicesMACKey()
        let store = try PairedDevicesStore(storage: storage, macKey: macKey)
        try await store.add(name: "iPad", publicKey: Array(repeating: 7, count: 32), role: .viewer)
        let original = try #require(try storage.read())
        let forged = try #require(String(data: original, encoding: .utf8)?.replacingOccurrences(of: "\"view\" : true", with: "\"view\" : false"))
        try storage.write(Data(forged.utf8))

        let reopened = try PairedDevicesStore(storage: storage, macKey: macKey)
        #expect(await reopened.integrityFailure)
        #expect(await reopened.integrityNoticePending)
        #expect(await reopened.devices.isEmpty)
        #expect(storage.quarantinedData == nil)

        try await reopened.add(name: "Mac", publicKey: Array(repeating: 9, count: 32), role: .viewer)
        #expect(storage.quarantinedData == Data(forged.utf8))
        #expect(!(await reopened.integrityFailure))
        #expect(await reopened.integrityNoticePending)
        await reopened.acknowledgeIntegrityNotice()
        #expect(!(await reopened.integrityNoticePending))
    }

    @Test func changesReportAddRemoveAndPermissionUpdates() async throws {
        let store = try PairedDevicesStore(storage: InMemoryPairedDevicesStorage(), macKey: InMemoryPairedDevicesMACKey())
        var iterator = await store.changes().makeAsyncIterator()
        let key = [UInt8](repeating: 3, count: 32)
        let device = try await store.add(name: "iPad", publicKey: key, role: .viewer)
        try await store.setPermissions(id: device.id, DevicePermissions(view: true, input: false, clipboard: false, audio: false))
        try await store.remove(id: device.id)
        #expect(await iterator.next() == .added(device.id))
        #expect(await iterator.next() == .permissionsChanged(device.id))
        #expect(await iterator.next() == .removed(device.id))
    }

    @Test func lastAddressIsStoredAndSurvivesReload() async throws {
        let storage = InMemoryPairedDevicesStorage()
        let macKey = InMemoryPairedDevicesMACKey()
        let store = try PairedDevicesStore(storage: storage, macKey: macKey)
        let device = try await store.add(name: "Mac", publicKey: Array(repeating: 5, count: 32), role: .host)
        try await store.setLastAddress(id: device.id, "192.168.1.17:47800")
        let reopened = try PairedDevicesStore(storage: storage, macKey: macKey)
        #expect(await reopened.devices.first?.lastAddress == "192.168.1.17:47800")
        #expect(!(await reopened.integrityFailure))
    }
}
