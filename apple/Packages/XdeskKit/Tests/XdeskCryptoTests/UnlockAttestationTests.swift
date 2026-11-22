import CryptoKit
import Foundation
import Testing
@testable import XdeskCrypto

/// Chữ ký mở khoá P-256, nonce một lần, và quy tắc đăng ký khoá (TOFU, fail-closed).
struct UnlockAttestationTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let macKey = InMemoryPairedDevicesMACKey(key: SymmetricKey(data: [UInt8](repeating: 0x42, count: 32)))
    private let phoneKey = P256.Signing.PrivateKey()

    private let hostKey = [UInt8](repeating: 0xA1, count: 32)
    private let viewerKey = [UInt8](repeating: 0xB2, count: 32)

    private func message(_ nonce: [UInt8], host: [UInt8]? = nil, viewer: [UInt8]? = nil) -> [UInt8] {
        UnlockKeyFormat.signedMessage(hostKey: host ?? hostKey, viewerKey: viewer ?? viewerKey, nonce: nonce)
    }

    private func sign(_ key: P256.Signing.PrivateKey, nonce: [UInt8], host: [UInt8]? = nil, viewer: [UInt8]? = nil) throws -> [UInt8] {
        Array(try key.signature(for: message(nonce, host: host, viewer: viewer)).derRepresentation)
    }

    private func consume(_ book: inout UnlockChallengeBook, _ sig: [UInt8], at now: Date? = nil) -> UnlockChallengeBook.Failure? {
        book.consume(publicKey: pub(phoneKey), hostKey: hostKey, viewerKey: viewerKey, derSignature: sig, now: now ?? t0)
    }

    private func pub(_ key: P256.Signing.PrivateKey) -> [UInt8] { Array(key.publicKey.x963Representation) }

    // MARK: Chữ ký

    @Test func validSignaturePasses() throws {
        var book = UnlockChallengeBook()
        let nonce = book.issue(now: t0)
        let result = consume(&book, try sign(phoneKey, nonce: nonce), at: t0)
        #expect(result == nil)
    }

    @Test func signatureFromAnotherKeyFails() throws {
        var book = UnlockChallengeBook()
        let nonce = book.issue(now: t0)
        let attacker = P256.Signing.PrivateKey()
        #expect(consume(&book, try sign(attacker, nonce: nonce), at: t0) == .badSignature)
    }

    @Test func signatureOverAnotherNonceFails() throws {
        var book = UnlockChallengeBook()
        _ = book.issue(now: t0)
        let other = [UInt8](repeating: 9, count: 32)
        #expect(consume(&book, try sign(phoneKey, nonce: other), at: t0) == .badSignature)
    }

    @Test func signatureWithoutDomainPrefixFails() throws {
        var book = UnlockChallengeBook()
        let nonce = book.issue(now: t0)
        let raw = Array(try phoneKey.signature(for: nonce).derRepresentation)
        #expect(consume(&book, raw, at: t0) == .badSignature)
    }

    @Test func nonceIsSingleUse() throws {
        var book = UnlockChallengeBook()
        let nonce = book.issue(now: t0)
        let sig = try sign(phoneKey, nonce: nonce)
        #expect(consume(&book, sig, at: t0) == nil)
        #expect(consume(&book, sig, at: t0) == .noChallenge)
    }

    @Test func failedAttemptAlsoBurnsTheNonce() throws {
        var book = UnlockChallengeBook()
        let nonce = book.issue(now: t0)
        #expect(consume(&book, [1, 2, 3], at: t0) == .badSignature)
        #expect(consume(&book, try sign(phoneKey, nonce: nonce), at: t0) == .noChallenge)
    }

    @Test func expiredNonceFails() throws {
        var book = UnlockChallengeBook(ttl: 30)
        let nonce = book.issue(now: t0)
        let sig = try sign(phoneKey, nonce: nonce)
        #expect(consume(&book, sig, at: t0.addingTimeInterval(31)) == .expired)
    }

    @Test func nonceAtTTLBoundaryStillValid() throws {
        var book = UnlockChallengeBook(ttl: 30)
        let nonce = book.issue(now: t0)
        #expect(consume(&book, try sign(phoneKey, nonce: nonce), at: t0.addingTimeInterval(30)) == nil)
    }

    @Test func newChallengeReplacesTheOldOne() throws {
        var book = UnlockChallengeBook()
        let first = book.issue(now: t0)
        let second = book.issue(now: t0)
        #expect(first != second && second.count == 32)
        #expect(consume(&book, try sign(phoneKey, nonce: first), at: t0) == .badSignature)
    }

    @Test func discardRemovesPendingNonce() {
        var book = UnlockChallengeBook()
        _ = book.issue(now: t0)
        book.discard()
        #expect(consume(&book, [], at: t0) == .noChallenge)
    }

    @Test func malformedDERAndKeysNeverPass() throws {
        let nonce = [UInt8](repeating: 3, count: 32)
        let msg = message(nonce)
        let good = try sign(phoneKey, nonce: nonce)
        #expect(UnlockKeyFormat.verify(publicKey: pub(phoneKey), message: msg, derSignature: good))
        #expect(!UnlockKeyFormat.verify(publicKey: pub(phoneKey), message: msg, derSignature: []))
        #expect(!UnlockKeyFormat.verify(publicKey: pub(phoneKey), message: msg, derSignature: Array(good.dropLast())))
        #expect(!UnlockKeyFormat.verify(publicKey: pub(phoneKey), message: msg, derSignature: good + [0]))
        #expect(!UnlockKeyFormat.verify(publicKey: pub(phoneKey), message: msg, derSignature: [UInt8](repeating: 0xFF, count: 70)))
        #expect(!UnlockKeyFormat.verify(publicKey: Array(pub(phoneKey).dropLast()), message: msg, derSignature: good))
        #expect(!UnlockKeyFormat.verify(publicKey: [UInt8](repeating: 4, count: 65), message: msg, derSignature: good))
    }

    @Test func rawFixedLengthSignatureIsRejectedNotDER() throws {
        let nonce = [UInt8](repeating: 3, count: 32)
        let raw = Array(try phoneKey.signature(for: message(nonce)).rawRepresentation)
        #expect(!UnlockKeyFormat.verify(publicKey: pub(phoneKey), message: message(nonce), derSignature: raw))
    }

    private func b64(_ v: JSONDict, _ key: String) throws -> [UInt8] { Array(try #require(Data(base64Encoded: try v.str(key)))) }

    @Test func sharedVectorVerifies() throws {
        let vector = try #require(try Vectors.load("control-frames.json")["unlockAttestation"] as? JSONDict)
        let pubKey = try #require(Data(base64Encoded: try vector.str("publicKey")))
        let nonce = try #require(Data(base64Encoded: try vector.str("nonce")))
        let sig = try #require(Data(base64Encoded: try vector.str("signature")))
        #expect(try vector.str("domain") == "xdesk v1 unlock")
        #expect(UnlockKeyFormat.verify(publicKey: Array(pubKey), message: UnlockKeyFormat.signedMessage(hostKey: try b64(vector, "hostKey"), viewerKey: try b64(vector, "viewerKey"), nonce: Array(nonce)), derSignature: Array(sig)))
    }

    // MARK: Bản ghi thiết bị

    private func device(unlockKey: [UInt8]? = nil) -> PairedDevice {
        var d = PairedDevice(name: "iPhone", publicKey: [UInt8](repeating: 5, count: 32), role: .viewer, createdAt: t0,
                             permissions: DevicePermissions(view: true, input: true, clipboard: false, audio: false, unlock: true))
        d.unlockKey = unlockKey
        return d
    }

    private func encoded(_ d: PairedDevice) throws -> String {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        return String(decoding: try enc.encode(d), as: UTF8.self)
    }

    @Test func recordWithoutKeyOmitsTheFieldSoOldHMACsStayValid() throws {
        #expect(try !encoded(device()).contains("unlockKey"))
    }

    @Test func recordRoundTripsUnlockKey() throws {
        let key = pub(phoneKey)
        let json = try encoded(device(unlockKey: key))
        #expect(json.contains("unlockKey"))
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        #expect(try dec.decode(PairedDevice.self, from: Data(json.utf8)).unlockKey == key)
    }

    @Test func recordWithGarbageUnlockKeyIsRejected() throws {
        let json = try encoded(device()).replacingOccurrences(of: "\"role\"", with: "\"unlockKey\":\"AAAA\",\"role\"")
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        #expect(throws: DecodingError.self) { _ = try dec.decode(PairedDevice.self, from: Data(json.utf8)) }
    }

    @Test func fileWithoutKeysKeepsItsMacAfterReload() async throws {
        let storage = InMemoryPairedDevicesStorage()
        let store = try PairedDevicesStore(storage: storage, macKey: macKey, now: { [t0] in t0 })
        try await store.add(name: "iPad", publicKey: [UInt8](repeating: 1, count: 32), role: .viewer)
        let reloaded = try PairedDevicesStore(storage: storage, macKey: macKey)
        #expect(await !reloaded.integrityFailure)
    }

    @Test func enrolledKeyIsHMACCoveredAndSurvivesReload() async throws {
        let storage = InMemoryPairedDevicesStorage()
        let store = try PairedDevicesStore(storage: storage, macKey: macKey, now: { [t0] in t0 })
        let id = try await store.add(name: "iPhone", publicKey: [UInt8](repeating: 1, count: 32), role: .viewer).id
        try await store.setPermissions(id: id, DevicePermissions(view: true, input: true, clipboard: false, audio: false, unlock: true))
        #expect(try await store.enrollUnlockKey(id: id, key: pub(phoneKey)) == .enrolled)
        let reloaded = try PairedDevicesStore(storage: storage, macKey: macKey)
        #expect(await !reloaded.integrityFailure)
        #expect(await reloaded.devices.first?.unlockKey == pub(phoneKey))
        // Sửa tay file để thay khoá → sai MAC → danh sách bị bỏ (fail-closed).
        let text = String(decoding: try #require(try storage.read()), as: UTF8.self)
        let tampered = text.replacingOccurrences(of: Base64URL.encode(pub(phoneKey)), with: Base64URL.encode(pub(P256.Signing.PrivateKey())))
        try storage.write(Data(tampered.utf8))
        let after = try PairedDevicesStore(storage: storage, macKey: macKey)
        #expect(await after.integrityFailure)
        #expect(await after.devices.isEmpty)
    }

    // MARK: Quy tắc đăng ký

    private func seededStore(unlock: Bool = true, storage: InMemoryPairedDevicesStorage = InMemoryPairedDevicesStorage()) async throws -> (PairedDevicesStore, String) {
        let store = try PairedDevicesStore(storage: storage, macKey: macKey, now: { [t0] in t0 })
        let id = try await store.add(name: "iPhone", publicKey: [UInt8](repeating: 1, count: 32), role: .viewer).id
        try await store.setPermissions(id: id, DevicePermissions(view: true, input: true, clipboard: false, audio: false, unlock: unlock))
        return (store, id)
    }

    @Test func enrollmentRequiresUnlockPermission() async throws {
        let (store, id) = try await seededStore(unlock: false)
        #expect(try await store.enrollUnlockKey(id: id, key: pub(phoneKey)) == .notPermitted)
        #expect(await store.devices.first?.unlockKey == nil)
    }

    @Test func enrollmentRejectsInvalidKeysAndUnknownDevices() async throws {
        let (store, id) = try await seededStore(unlock: true)
        #expect(try await store.enrollUnlockKey(id: id, key: [4, 1, 2]) == .invalidKey)
        #expect(try await store.enrollUnlockKey(id: "nope", key: pub(phoneKey)) == .notPermitted)
    }

    @Test func firstKeyWinsAndDifferentKeyNeverOverwrites() async throws {
        let (store, id) = try await seededStore(unlock: true)
        #expect(try await store.enrollUnlockKey(id: id, key: pub(phoneKey)) == .enrolled)
        #expect(try await store.enrollUnlockKey(id: id, key: pub(phoneKey)) == .alreadyEnrolled)
        let other = pub(P256.Signing.PrivateKey())
        #expect(try await store.enrollUnlockKey(id: id, key: other) == .mismatch)
        #expect(await store.devices.first?.unlockKey == pub(phoneKey))
    }

    @Test func clearingTheKeyAllowsReEnrollment() async throws {
        let (store, id) = try await seededStore(unlock: true)
        _ = try await store.enrollUnlockKey(id: id, key: pub(phoneKey))
        try await store.clearUnlockKey(id: id)
        let other = pub(P256.Signing.PrivateKey())
        #expect(try await store.enrollUnlockKey(id: id, key: other) == .enrolled)
        #expect(await store.devices.first?.unlockKey == other)
    }

    @Test func turningUnlockPermissionOffClearsTheKey() async throws {
        let (store, id) = try await seededStore(unlock: true)
        _ = try await store.enrollUnlockKey(id: id, key: pub(phoneKey))
        try await store.setPermissions(id: id, DevicePermissions(view: true, input: true, clipboard: false, audio: false, unlock: false))
        #expect(await store.devices.first?.unlockKey == nil)
    }

    @Test func changingOtherPermissionsKeepsTheKey() async throws {
        let (store, id) = try await seededStore(unlock: true)
        _ = try await store.enrollUnlockKey(id: id, key: pub(phoneKey))
        try await store.setPermissions(id: id, DevicePermissions(view: true, input: false, clipboard: true, audio: false, unlock: true))
        #expect(await store.devices.first?.unlockKey == pub(phoneKey))
    }

    // MARK: Cửa sổ đăng ký, schema, dấu vân tay

    private final class TestClock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private func clockedStore(_ clock: TestClock, storage: InMemoryPairedDevicesStorage = InMemoryPairedDevicesStorage()) async throws -> (PairedDevicesStore, String) {
        let store = try PairedDevicesStore(storage: storage, macKey: macKey, now: { clock.now })
        let id = try await store.add(name: "iPhone", publicKey: [UInt8](repeating: 1, count: 32), role: .viewer).id
        return (store, id)
    }

    private let unlockOn = DevicePermissions(view: true, input: true, clipboard: false, audio: false, unlock: true)

    @Test func enrollmentOnlyWithinFiveMinutesOfUserAction() async throws {
        let clock = TestClock(t0)
        let (store, id) = try await clockedStore(clock)
        try await store.setPermissions(id: id, unlockOn)
        clock.now = t0.addingTimeInterval(PairedDevicesStore.unlockEnrollmentWindow + 1)
        #expect(try await store.enrollUnlockKey(id: id, key: pub(phoneKey)) == .windowClosed)
        try await store.clearUnlockKey(id: id)
        #expect(try await store.enrollUnlockKey(id: id, key: pub(phoneKey)) == .enrolled)
    }

    @Test func deviceThatAlreadyHadUnlockOnNeedsAResetToEnroll() async throws {
        let clock = TestClock(t0)
        let storage = InMemoryPairedDevicesStorage()
        let (store, id) = try await clockedStore(clock, storage: storage)
        try await store.setPermissions(id: id, unlockOn)
        // Khởi động lại: cửa sổ chỉ nằm trong bộ nhớ nên đóng.
        let reopened = try PairedDevicesStore(storage: storage, macKey: macKey, now: { clock.now })
        #expect(try await reopened.enrollUnlockKey(id: id, key: pub(phoneKey)) == .windowClosed)
        try await reopened.clearUnlockKey(id: id)
        #expect(try await reopened.enrollUnlockKey(id: id, key: pub(phoneKey)) == .enrolled)
    }

    @Test func enrollmentWindowIsSingleUse() async throws {
        let (store, id) = try await seededStore(unlock: true)
        #expect(try await store.enrollUnlockKey(id: id, key: pub(phoneKey)) == .enrolled)
        try await store.clearUnlockKey(id: id) // mở lại
        #expect(try await store.enrollUnlockKey(id: id, key: pub(phoneKey)) == .enrolled)
        try await store.setPermissions(id: id, DevicePermissions(view: true, input: true, clipboard: false, audio: false, unlock: false))
        #expect(try await store.enrollUnlockKey(id: id, key: pub(phoneKey)) == .notPermitted)
    }

    @Test func fingerprintIsStableAndFormatted() {
        let f = UnlockKeyFormat.fingerprint(of: [UInt8](repeating: 4, count: 65))
        #expect(f.count == 19 && f.split(separator: "-").count == 4)
        #expect(f == UnlockKeyFormat.fingerprint(of: [UInt8](repeating: 4, count: 65)))
        #expect(f != UnlockKeyFormat.fingerprint(of: [UInt8](repeating: 5, count: 65)))
    }

    @Test func signatureIsBoundToBothStaticKeys() throws {
        var book = UnlockChallengeBook()
        let nonce = book.issue(now: t0)
        let sig = try sign(phoneKey, nonce: nonce, host: [UInt8](repeating: 9, count: 32))
        #expect(consume(&book, sig) == .badSignature)
        let nonce2 = book.issue(now: t0)
        #expect(consume(&book, try sign(phoneKey, nonce: nonce2, viewer: [UInt8](repeating: 9, count: 32))) == .badSignature)
    }

    /// Mô phỏng đúng `guard` của bản cũ (`schemaVersion == 1` mới nạp): file có khoá phải bị bản cũ từ chối chứ không bị ghi đè/cách ly.
    @Test func fileWithUnlockKeyIsRefusedByOldSchemaCheckAndLeftIntact() async throws {
        let storage = InMemoryPairedDevicesStorage()
        let (store, id) = try await seededStore(storage: storage)
        _ = try await store.enrollUnlockKey(id: id, key: pub(phoneKey))
        let before = try #require(try storage.read())
        let object = try #require(JSONSerialization.jsonObject(with: before) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == PairedDevicesStore.unlockKeySchemaVersion)
        let oldSupported = 1
        #expect((object["schemaVersion"] as? Int) != oldSupported, "bản cũ sẽ ném unsupportedSchema trước bước kiểm HMAC")
        #expect(try storage.read() == before)
        #expect(try await PairedDevicesStore(storage: storage, macKey: macKey).devices.first?.unlockKey == pub(phoneKey))
    }

    @Test func fileWithoutKeysStaysSchemaOneForOldBuilds() async throws {
        let storage = InMemoryPairedDevicesStorage()
        let (store, id) = try await seededStore(storage: storage)
        _ = try await store.enrollUnlockKey(id: id, key: pub(phoneKey))
        try await store.clearUnlockKey(id: id)
        let data = try #require(try storage.read())
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == PairedDevicesStore.schemaVersion)
    }
}
