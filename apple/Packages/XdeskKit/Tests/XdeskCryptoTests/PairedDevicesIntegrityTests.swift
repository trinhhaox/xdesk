import CryptoKit
import Foundation
import Testing
@testable import XdeskCrypto

/// Tra cứu theo khoá đầy đủ (M1) và toàn vẹn file danh sách thiết bị bằng HMAC (M3).
struct PairedDevicesIntegrityTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let macKey = InMemoryPairedDevicesMACKey(key: SymmetricKey(data: [UInt8](repeating: 0x42, count: 32)))

    @Test func lookupRequiresTheFullPublicKeyNotJustTheFingerprint() async throws {
        let store = try PairedDevicesStore(storage: InMemoryPairedDevicesStorage(), macKey: macKey, now: { [t0] in t0 })
        let key = Array(Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation)
        try await store.add(name: "iPad", publicKey: key, role: .viewer)
        #expect(await store.device(publicKey: key)?.name == "iPad")
        for index in [0, 7, 8, 31] {
            var other = key
            other[index] ^= 1
            #expect(await store.device(publicKey: other) == nil, "byte \(index)")
        }
        #expect(await store.device(publicKey: Array(key.dropLast())) == nil)
        #expect(await store.device(publicKey: []) == nil)
    }

    @Test func duplicateEntriesForOneIdAreCorruptNotSilentlyMerged() async throws {
        let storage = try await seededStorage()
        let json = try fileText(storage)
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        var doubled = object
        doubled["devices"] = try #require(object["devices"] as? [Any]) + (try #require(object["devices"] as? [Any]))
        try storage.write(try JSONSerialization.data(withJSONObject: doubled))
        #expect(throws: IdentityStoreError.corrupt) { _ = try PairedDevicesStore(storage: storage, macKey: macKey) }
    }

    // MARK: - Toàn vẹn file (M3)

    private func seededStorage() async throws -> InMemoryPairedDevicesStorage {
        let storage = InMemoryPairedDevicesStorage()
        let store = try PairedDevicesStore(storage: storage, macKey: macKey, now: { [t0] in t0 })
        try await store.add(name: "iPad", publicKey: [UInt8](repeating: 1, count: 32), role: .viewer)
        return storage
    }

    @Test func fileCarriesAMacAndReloadsCleanly() async throws {
        let storage = try await seededStorage()
        let json = try fileText(storage)
        #expect(json.contains("\"mac\""))
        let reloaded = try PairedDevicesStore(storage: storage, macKey: macKey)
        #expect(await reloaded.devices.count == 1)
        #expect(await !reloaded.integrityFailure)
    }

    @Test func editedFileIsRefusedAsEmptyWithIntegrityFlag() async throws {
        let storage = try await seededStorage()
        let json = try fileText(storage)
        let escalated = json.replacingOccurrences(of: "\"input\" : true", with: "\"input\" : false")
            .replacingOccurrences(of: "\"clipboard\" : false", with: "\"clipboard\" : true")
        #expect(escalated != json)
        try storage.write(Data(escalated.utf8))
        let store = try PairedDevicesStore(storage: storage, macKey: macKey)
        #expect(await store.devices.isEmpty)
        #expect(await store.integrityFailure)
        #expect(await store.device(publicKey: [UInt8](repeating: 1, count: 32)) == nil)
    }

    @Test func injectedDeviceWithoutValidMacIsRefused() async throws {
        let storage = try await seededStorage()
        let attacker = PairedDevice(name: "evil", publicKey: [UInt8](repeating: 9, count: 32), role: .viewer, createdAt: t0)
        let forged = #"{"schemaVersion":1,"devices":[{"id":"\#(attacker.id)","name":"evil","pub":"\#(Base64URL.encode(attacker.publicKey))","role":1,"createdAt":"2023-11-14T22:13:20Z","permissions":{"view":true,"input":true,"clipboard":true,"audio":true}}]}"#
        for body in [forged, forged.replacingOccurrences(of: "}]}", with: "}],\"mac\":\"AAAA\"}"),
                     forged.replacingOccurrences(of: "}]}", with: "}],\"mac\":\"\(Base64URL.encode([UInt8](repeating: 0, count: 32)))\"}")] {
            try storage.write(Data(body.utf8))
            let store = try PairedDevicesStore(storage: storage, macKey: macKey)
            let empty = await store.devices.isEmpty, flagged = await store.integrityFailure
            #expect(empty && flagged)
        }
    }

    @Test func wrongMacKeyRefusesAnOtherwiseValidFile() async throws {
        let storage = try await seededStorage()
        let other = InMemoryPairedDevicesMACKey(key: SymmetricKey(data: [UInt8](repeating: 0x43, count: 32)))
        let store = try PairedDevicesStore(storage: storage, macKey: other)
        let empty = await store.devices.isEmpty, flagged = await store.integrityFailure
        #expect(empty && flagged)
    }

    @Test func nextSuccessfulWriteReSignsAndClearsTheFlag() async throws {
        let storage = try await seededStorage()
        try storage.write(Data(#"{"schemaVersion":1,"devices":[]}"#.utf8))
        let store = try PairedDevicesStore(storage: storage, macKey: macKey, now: { [t0] in t0 })
        #expect(await store.integrityFailure)
        try await store.add(name: "new", publicKey: [UInt8](repeating: 2, count: 32), role: .viewer)
        #expect(await !store.integrityFailure)
        let reloaded = try PairedDevicesStore(storage: storage, macKey: macKey)
        let names = await reloaded.devices.map(\.name), flagged = await reloaded.integrityFailure
        #expect(names == ["new"] && !flagged)
    }
}
