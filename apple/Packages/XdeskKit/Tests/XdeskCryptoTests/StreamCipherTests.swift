import Testing
@testable import XdeskCrypto

struct StreamCipherTests {
    private func sender() -> StreamSender { StreamSender(key: fixedKey(3)) }
    private func receiver() -> StreamReceiver { StreamReceiver(key: fixedKey(3)) }

    @Test func orderedRoundTrip() throws {
        var tx = sender(), rx = receiver()
        for (index, kind) in [UInt8(2), 3, 4, 2].enumerated() {
            let plain = [UInt8](repeating: UInt8(index), count: index * 100)
            let sealed = try tx.seal(kind: kind, plaintext: plain)
            #expect(sealed.count == plain.count + 16)
            expectEqual(try rx.open(kind: kind, ciphertext: sealed), plain)
        }
    }

    @Test func kindAndLengthAreAuthenticated() throws {
        var tx = sender(), rx = receiver()
        let sealed = try tx.seal(kind: 2, plaintext: Array("{}".utf8))
        #expect(throws: CryptoError.authenticationFailed) { _ = try rx.open(kind: 3, ciphertext: sealed) }
    }

    @Test func reorderOrReplayBreaksTheStream() throws {
        var tx = sender(), rx = receiver()
        let a = try tx.seal(kind: 2, plaintext: [1])
        let b = try tx.seal(kind: 2, plaintext: [2])
        #expect(throws: CryptoError.authenticationFailed) { _ = try rx.open(kind: 2, ciphertext: b) }
        expectEqual(try rx.open(kind: 2, ciphertext: a), [1])
        #expect(throws: CryptoError.authenticationFailed) { _ = try rx.open(kind: 2, ciphertext: a) }
    }

    @Test func tamperAndTruncation() throws {
        var tx = sender(), rx = receiver()
        var sealed = try tx.seal(kind: 2, plaintext: [1, 2, 3])
        #expect(throws: CryptoError.messageTooShort) { _ = try rx.open(kind: 2, ciphertext: [1, 2]) }
        sealed[0] ^= 1
        #expect(throws: CryptoError.authenticationFailed) { _ = try rx.open(kind: 2, ciphertext: sealed) }
    }

    @Test func frameSizeLimit() throws {
        var tx = sender()
        expectEqual(try tx.seal(kind: 2, plaintext: [UInt8](repeating: 0, count: 1_048_559)).count, 1_048_575)
        #expect(throws: CryptoError.messageTooLarge) { _ = try tx.seal(kind: 2, plaintext: [UInt8](repeating: 0, count: 1_048_560)) }
    }

    @Test func rekeyKeepsBothSidesInSyncAndChangesKey() throws {
        var tx = sender(), rx = receiver()
        let before = try tx.seal(kind: 2, plaintext: [1])
        expectEqual(try rx.open(kind: 2, ciphertext: before), [1])
        tx.rekey()
        let after = try tx.seal(kind: 2, plaintext: [2])
        var stale = receiver()
        _ = try stale.open(kind: 2, ciphertext: before)
        #expect(throws: CryptoError.authenticationFailed) { _ = try stale.open(kind: 2, ciphertext: after) }
        rx.rekey()
        expectEqual(try rx.open(kind: 2, ciphertext: after), [2])
    }
}
