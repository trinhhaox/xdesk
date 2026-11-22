import CryptoKit
import Foundation
import Testing
@testable import XdeskCrypto

struct DeviceStoresTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let macKey = InMemoryPairedDevicesMACKey(key: SymmetricKey(data: [UInt8](repeating: 0x42, count: 32)))

    @Test func fingerprintFormat() {
        let key = [UInt8](repeating: 0, count: 32)
        let fingerprint = DeviceFingerprint.make(publicKey: key)
        #expect(fingerprint == "6668-7AAD-F862-BD77")
        let expected = SHA256.hash(data: key).prefix(8).map { String(format: "%02X", $0) }.joined()
        #expect(fingerprint.replacingOccurrences(of: "-", with: "") == expected)
        #expect(fingerprint.split(separator: "-").map(\.count) == [4, 4, 4, 4])
    }

    @Test func inMemoryIdentityIsStableUntilDeleted() throws {
        let store = InMemoryDeviceIdentityStore()
        let first = try store.loadOrCreate()
        #expect(try store.loadOrCreate().publicKey == first.publicKey)
        try store.delete()
        #expect(try store.loadOrCreate().publicKey != first.publicKey)
        #expect(first.fingerprint == DeviceFingerprint.make(publicKey: first.publicKey))
    }

    @Test func keychainIdentityPersistsAndCleansUp() throws {
        let store = KeychainDeviceIdentityStore(service: "vn.xox.xdesk.tests.\(UUID().uuidString)", policy: .preferred)
        defer { try? store.delete() }
        let first = try store.loadOrCreate()
        #expect(try store.loadOrCreate().publicKey == first.publicKey)
        #expect(store.backend != nil)
        try store.delete()
        #expect(try store.loadOrCreate().publicKey != first.publicKey)
    }

    /// Binary không có Team ID/entitlement (như `swift test`) không có data-protection keychain: `.required` phải báo lỗi rõ,
    /// không âm thầm hạ xuống login keychain; app đã ký thì dùng được và `backend == .dataProtection`.
    @Test func requiredPolicyReportsMissingDataProtectionEntitlementClearly() throws {
        let store = KeychainDeviceIdentityStore(service: "vn.xox.xdesk.tests.\(UUID().uuidString)", policy: .required)
        defer { try? store.delete() }
        do {
            _ = try store.loadOrCreate()
            #expect(store.backend == .dataProtection)
        } catch {
            #expect(error as? IdentityStoreError == .dataProtectionKeychainUnavailable)
            #expect(store.backend == nil)
        }
    }

    @Test func keychainMACKeyIsStable32Bytes() throws {
        let store = KeychainPairedDevicesMACKeyStore(service: "vn.xox.xdesk.tests.mac.\(UUID().uuidString)", policy: .preferred)
        defer { try? store.delete() }
        let first = try store.loadOrCreate()
        let again = try store.loadOrCreate()
        #expect(first.bytes.count == 32 && first.bytes == again.bytes)
        try store.delete()
        #expect(try store.loadOrCreate().bytes != first.bytes)
    }

    @Test func newDeviceGetsDefaultPermissionsAndPersists() async throws {
        let storage = InMemoryPairedDevicesStorage()
        let store = try PairedDevicesStore(storage: storage, macKey: macKey, now: { [t0] in t0 })
        let key = Array(Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation)
        let device = try await store.add(name: "iPad", publicKey: key, role: .viewer)
        #expect(device.permissions == DevicePermissions(view: true, input: true, clipboard: false, audio: false))
        #expect(device.id == DeviceFingerprint.make(publicKey: key))
        #expect(device.createdAt == t0 && device.lastSeen == nil)

        let reloaded = try PairedDevicesStore(storage: storage, macKey: macKey)
        #expect(await reloaded.devices == [device])
        #expect(await reloaded.device(publicKey: key) == device)
    }

    @Test func updateRemoveAndRollbackOnWriteFailure() async throws {
        let storage = InMemoryPairedDevicesStorage()
        let store = try PairedDevicesStore(storage: storage, macKey: macKey, now: { [t0] in t0 + 60 })
        let key = [UInt8](repeating: 9, count: 32)
        let device = try await store.add(name: "A", publicKey: key, role: .viewer)
        try await store.setPermissions(id: device.id, DevicePermissions(view: true, input: false, clipboard: true, audio: true))
        try await store.markSeen(id: device.id)
        let renamed = try await store.add(name: "A2", publicKey: key, role: .host)
        #expect(renamed.name == "A2" && renamed.permissions.clipboard && renamed.lastSeen == t0 + 60)
        #expect(await store.devices.count == 1)
        #expect(try await store.remove(id: device.id))
        #expect(try await !store.remove(id: device.id))
        let emptied = try PairedDevicesStore(storage: storage, macKey: macKey)
        #expect(await emptied.devices.isEmpty)

        let failing = try PairedDevicesStore(storage: FailingStorage(), macKey: macKey)
        await #expect(throws: FailingStorage.Failure.self) { _ = try await failing.add(name: "x", publicKey: key, role: .host) }
        #expect(await failing.devices.isEmpty)
    }

    @Test func fileFormatAndVersioning() async throws {
        let storage = InMemoryPairedDevicesStorage()
        let store = try PairedDevicesStore(storage: storage, macKey: macKey, now: { [t0] in t0 })
        let key = [UInt8](repeating: 1, count: 32)
        try await store.add(name: "Mac", publicKey: key, role: .host)
        let json = try fileText(storage)
        #expect(json.contains("\"schemaVersion\" : 1"))
        for field in ["\"id\"", "\"name\"", "\"pub\"", "\"role\"", "\"createdAt\"", "\"permissions\"", "\"clipboard\" : false"] {
            #expect(json.contains(field), "\(field)")
        }
        #expect(json.contains(Base64URL.encode(key)))
        #expect(!json.contains("lastSeen"))

        try storage.write(Data(#"{"schemaVersion":2,"devices":[]}"#.utf8))
        #expect(throws: IdentityStoreError.unsupportedSchema(2)) { _ = try PairedDevicesStore(storage: storage, macKey: macKey) }
        try storage.write(Data("not json".utf8))
        #expect(throws: IdentityStoreError.corrupt) { _ = try PairedDevicesStore(storage: storage, macKey: macKey) }
    }

    @Test func tamperedIdOrKeyIsRejectedOnLoad() async throws {
        let storage = InMemoryPairedDevicesStorage()
        let key = [UInt8](repeating: 1, count: 32)
        try await PairedDevicesStore(storage: storage, macKey: macKey, now: { [t0] in t0 }).add(name: "x", publicKey: key, role: .viewer)
        let good = try fileText(storage)
        let id = DeviceFingerprint.make(publicKey: key)
        let count = await (try PairedDevicesStore(storage: storage, macKey: macKey)).devices.count
        #expect(count == 1)
        try storage.write(Data(good.replacingOccurrences(of: id, with: "0000-0000-0000-0000").utf8))
        #expect(throws: IdentityStoreError.corrupt) { _ = try PairedDevicesStore(storage: storage, macKey: macKey) }
    }

    @Test func fileStorageWritesPrivateFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("xdesk-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = FilePairedDevicesStorage(url: dir.appendingPathComponent("sub/paired.json"))
        #expect(try storage.read() == nil)
        try storage.write(Data("{}".utf8))
        #expect(try storage.read() == Data("{}".utf8))
        let permissions = try FileManager.default.attributesOfItem(atPath: storage.url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        let directory = try FileManager.default.attributesOfItem(atPath: storage.url.deletingLastPathComponent().path)[.posixPermissions] as? Int
        #expect(directory == 0o700)
        try storage.write(Data("{\"second\":1}".utf8))
        #expect(try storage.read() == Data("{\"second\":1}".utf8))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: storage.url.deletingLastPathComponent().path)
        #expect(leftovers == ["paired.json"])
    }

    @Test func optInUnlockPreservesLegacyHmacCompatibility() async throws {
        let storage = InMemoryPairedDevicesStorage()
        let key = [UInt8](repeating: 3, count: 32)
        let store1 = try PairedDevicesStore(storage: storage, macKey: macKey, now: { [t0] in t0 })
        let added = try await store1.add(name: "iPhone", publicKey: key, role: .viewer)
        #expect(!added.permissions.unlock)
        let json = try fileText(storage)
        #expect(!json.contains("\"unlock\""))

        let store2 = try PairedDevicesStore(storage: storage, macKey: macKey)
        let failure2 = await store2.integrityFailure
        #expect(!failure2)
        #expect(await store2.devices.first?.permissions.unlock == false)

        try await store2.setPermissions(id: added.id, DevicePermissions(view: true, input: true, clipboard: false, audio: false, unlock: true))
        let store3 = try PairedDevicesStore(storage: storage, macKey: macKey)
        let failure3 = await store3.integrityFailure
        #expect(!failure3)
        #expect(await store3.devices.first?.permissions.unlock == true)
    }
}

func fileText(_ storage: InMemoryPairedDevicesStorage) throws -> String {
    let data = try unwrap(storage.read())
    return try unwrap(String(data: data, encoding: .utf8))
}

private struct FailingStorage: PairedDevicesStorage {
    struct Failure: Error {}
    func read() throws -> Data? { nil }
    func write(_ data: Data) throws { throw Failure() }
    func quarantine() throws {}
}
