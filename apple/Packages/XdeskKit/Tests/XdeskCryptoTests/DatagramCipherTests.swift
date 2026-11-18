import CryptoKit
import Testing
@testable import XdeskCrypto

struct DatagramCipherTests {
    private let header: [UInt8] = [1, 0x10, 0, 3, 0, 0, 0, 42, 0, 0, 0x80, 3, 0, 0, 0x13, 0x88]

    private func sender() -> DatagramSender { DatagramSender(key: fixedKey(7)) }
    private func receiver() -> DatagramReceiver { DatagramReceiver(key: fixedKey(7)) }

    @Test func roundTripKeepsHeaderPlain() throws {
        var tx = sender(), rx = receiver()
        let payload = Array("hello video".utf8)
        let packet = try tx.seal(header: header, payload: payload)
        #expect(Array(packet.prefix(16)) == header)
        #expect(packet.count == 16 + payload.count + DatagramFormat.overhead)
        #expect(!packet.contains(subsequence: payload))
        let opened = try rx.open(packet)
        #expect(opened == OpenedDatagram(header: header, payload: payload))
    }

    @Test func emptyPayloadAndMaxPayload() throws {
        var tx = sender(), rx = receiver()
        for size in [0, 1192] {
            let payload = [UInt8](repeating: 0x5A, count: size)
            expectEqual(try rx.open(tx.seal(header: header, payload: payload)).payload, payload)
        }
    }

    @Test func duplicateIsRejected() throws {
        var tx = sender(), rx = receiver()
        let packet = try tx.seal(header: header, payload: [1])
        _ = try rx.open(packet)
        #expect(throws: CryptoError.replayed) { _ = try rx.open(packet) }
    }

    @Test func reorderingWithinWindowIsAccepted() throws {
        var tx = sender(), rx = receiver()
        let packets = try (0..<5).map { try tx.seal(header: header, payload: [UInt8($0)]) }
        for index in [4, 2, 3, 0, 1] { expectEqual(try rx.open(packets[index]).payload, [UInt8(index)]) }
        for packet in packets { #expect(throws: CryptoError.replayed) { _ = try rx.open(packet) } }
    }

    @Test func oldAndBeyondWindowPacketsAreRejected() throws {
        var tx = sender(), rx = receiver()
        let first = try tx.seal(header: header, payload: [0])
        for _ in 0..<1500 { _ = try tx.seal(header: header, payload: []) }
        let late = try tx.seal(header: header, payload: [9])
        _ = try rx.open(late)
        #expect(throws: CryptoError.outsideReplayWindow) { _ = try rx.open(first) }
    }

    @Test func tamperingAnywhereIsDetectedAndDoesNotBurnTheCounter() throws {
        var tx = sender(), rx = receiver()
        let packet = try tx.seal(header: header, payload: Array("data".utf8))
        for index in 0..<packet.count {
            var bad = packet
            bad[index] ^= 0x01
            #expect(throws: (any Error).self) { _ = try rx.open(bad) }
        }
        expectEqual(try rx.open(packet).payload, Array("data".utf8))
    }

    @Test func headerIsAuthenticatedAsAD() throws {
        var tx = sender(), rx = receiver()
        var packet = try tx.seal(header: header, payload: [1, 2])
        packet[4] ^= 0xFF
        #expect(throws: CryptoError.authenticationFailed) { _ = try rx.open(packet) }
    }

    @Test func wrongKeyAndShortPacketsFail() throws {
        var tx = sender()
        var other = DatagramReceiver(key: fixedKey(8))
        let packet = try tx.seal(header: header, payload: [1])
        #expect(throws: CryptoError.authenticationFailed) { _ = try other.open(packet) }
        #expect(throws: CryptoError.datagramTooShort) { _ = try other.open(Array(packet.prefix(39))) }
        #expect(throws: CryptoError.invalidLength) { _ = try tx.seal(header: [1, 2], payload: []) }
    }

    @Test func rekeyAdvancesEpochAndReceiverFollows() throws {
        var tx = sender(), rx = receiver()
        let oldPacket = try tx.seal(header: header, payload: [1])
        let straggler = try tx.seal(header: header, payload: [2])
        try tx.rekey()
        expectEqual(tx.epoch, 1)
        expectEqual(tx.packetsInEpoch, 0)
        let fresh = try tx.seal(header: header, payload: [3])
        expectEqual(try rx.open(oldPacket).payload, [1])
        expectEqual(try rx.open(fresh).payload, [3])
        expectEqual(rx.epoch, 1)
        // gói muộn của epoch trước vẫn mở được; gói cũ mở lần hai bị coi là trùng.
        expectEqual(try rx.open(straggler).payload, [2])
        #expect(throws: CryptoError.replayed) { _ = try rx.open(oldPacket) }
    }

    @Test func forwardJumpWithinLookaheadIsAcceptedAfterTagVerifies() throws {
        for jump in 2...Int(DatagramReceiver.maxEpochLookahead) {
            var tx = sender(), rx = receiver()
            for _ in 0..<jump { try tx.rekey() }
            expectEqual(try rx.open(tx.seal(header: header, payload: [1])).payload, [1])
            expectEqual(rx.epoch, UInt32(jump))
        }
    }

    @Test func jumpBeyondLookaheadIsRejectedAndLeavesStateUntouched() throws {
        var tx = sender(), rx = receiver()
        let before = try tx.seal(header: header, payload: [1])
        for _ in 0...Int(DatagramReceiver.maxEpochLookahead) { try tx.rekey() }
        #expect(throws: CryptoError.unknownEpoch) { _ = try rx.open(tx.seal(header: header, payload: [2])) }
        expectEqual(rx.epoch, 0)
        expectEqual(try rx.open(before).payload, [1])
    }

    @Test func forgedFutureEpochNeverMovesTheReceiver() throws {
        var tx = sender(), rx = receiver()
        try tx.rekey()
        try tx.rekey()
        let genuine = try tx.seal(header: header, payload: [9])
        var forged = genuine
        forged[forged.count - 1] ^= 1
        #expect(throws: CryptoError.authenticationFailed) { _ = try rx.open(forged) }
        expectEqual(rx.epoch, 0)
        expectEqual(try rx.open(genuine).payload, [9])
        expectEqual(rx.epoch, 2)
    }

    @Test func afterAJumpThePreviousEpochStillAcceptsLatePacketsButOlderOnesDoNot() throws {
        var tx = sender(), rx = receiver()
        let epoch0 = try tx.seal(header: header, payload: [0])
        try tx.rekey()
        let epoch1 = try tx.seal(header: header, payload: [1])
        try tx.rekey()
        try tx.rekey()
        let epoch3 = try tx.seal(header: header, payload: [3])
        try tx.rekey()
        let epoch4 = try tx.seal(header: header, payload: [4])
        _ = try rx.open(epoch3)
        expectEqual(try rx.open(epoch4).payload, [4])
        #expect(throws: CryptoError.unknownEpoch) { _ = try rx.open(epoch1) }
        #expect(throws: CryptoError.unknownEpoch) { _ = try rx.open(epoch0) }
        // epoch 3 là "previous" của epoch 4 nên gói trùng bị coi là replay, không phải epoch lạ.
        #expect(throws: CryptoError.replayed) { _ = try rx.open(epoch3) }
    }

    @Test func epochFarBeyondTheLookaheadIsUnknown() throws {
        var tx = sender(), rx = receiver()
        let packet = try tx.seal(header: header, payload: [1])
        expectEqual(try rx.open(packet).payload, [1])
        #expect(throws: CryptoError.unknownEpoch) { _ = try rx.open(forgedPacket(epoch: UInt32.max)) }
    }

    private func forgedPacket(epoch: UInt32) -> [UInt8] {
        let nonce = UInt64(epoch) << 32
        return header + (0..<8).map { UInt8(truncatingIfNeeded: nonce >> (56 - 8 * UInt64($0))) } + [UInt8](repeating: 0, count: 17)
    }

    @Test func needsRekeyByCountAndByTime() throws {
        let start = ContinuousClock.now
        var tx = DatagramSender(key: fixedKey(1), now: start)
        expectEqual(tx.needsRekey(now: start), false)
        expectEqual(tx.needsRekey(now: start + .seconds(3599)), false)
        expectEqual(tx.needsRekey(now: start + .seconds(3600)), true)
        try tx.rekey(now: start + .seconds(3600))
        expectEqual(tx.needsRekey(now: start + .seconds(3601)), false)
    }

    @Test func nonceNeverRepeatsAcrossEpochs() throws {
        var tx = DatagramSender(key: fixedKey(2))
        var nonces = Set<[UInt8]>()
        for _ in 0..<3 {
            for _ in 0..<50 { nonces.insert(Array(try tx.seal(header: header, payload: []).dropFirst(16).prefix(8))) }
            try tx.rekey()
        }
        #expect(nonces.count == 150)
    }
}

private extension [UInt8] {
    func contains(subsequence needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, count >= needle.count else { return false }
        return (0...(count - needle.count)).contains { Array(self[$0..<$0 + needle.count]) == needle }
    }
}
