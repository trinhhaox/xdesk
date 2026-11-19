import Foundation
import Network
import Testing
import XdeskCrypto
import XdeskWire
@testable import XdeskTransport

@Suite struct SecureHandshakeLimitsTests {
    /// TCP thô tới host mã hoá, không nói gì.
    private func silentConnection(port: UInt16) async throws -> ControlConnection {
        try await ControlConnection.connect(host: "127.0.0.1", port: port, security: .encrypted)
    }

    @Test(.timeLimit(.minutes(1))) func perSourceCapRefusesTheThirdStalledConnection() async throws {
        let rig = try await SecureRig.make(maxPending: 8, maxPendingPerSource: 2)
        let a = try await silentConnection(port: rig.port)
        let b = try await silentConnection(port: rig.port)
        let c = try await silentConnection(port: rig.port)
        #expect(await eventually { await rig.listener.pendingHandshakes == 2 })
        // Kết nối thứ ba bị listener cắt ngay.
        #expect(await eventually { (try? await c.nextInbound()) == nil })
        #expect(await rig.listener.pendingHandshakes == 2)
        for conn in [a, b, c] { await conn.close() }
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func fullPendingPoolEvictsTheOldest() async throws {
        let rig = try await SecureRig.make(maxPending: 2, maxPendingPerSource: 8)
        let oldest = try await silentConnection(port: rig.port)
        #expect(await eventually { await rig.listener.pendingHandshakes == 1 })
        let second = try await silentConnection(port: rig.port)
        #expect(await eventually { await rig.listener.pendingHandshakes == 2 })
        let third = try await silentConnection(port: rig.port)
        #expect(await eventually { (try? await oldest.nextInbound()) == nil })
        #expect(await eventually { await rig.listener.pendingHandshakes == 2 })
        for conn in [oldest, second, third] { await conn.close() }
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func stalledHandshakeIsDroppedAfterThePerMessageDeadline() async throws {
        let rig = try await SecureRig.make()
        let stalled = try await silentConnection(port: rig.port)
        let started = ContinuousClock.now
        #expect(await eventually(seconds: 10) { await rig.listener.pendingHandshakes == 1 })
        #expect(await eventually(seconds: 10) { await rig.listener.pendingHandshakes == 0 })
        let elapsed = ContinuousClock.now - started
        #expect(elapsed >= .seconds(4) && elapsed < .seconds(8))
        await stalled.close()
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func realPairingStillWorksNextToStalledConnections() async throws {
        let rig = try await SecureRig.make(maxPending: 4, maxPendingPerSource: 2)
        let stalled = try await silentConnection(port: rig.port)
        _ = try await rig.pairWithQr()
        #expect(await rig.hostStore.devices.count == 1)
        await stalled.close()
        await rig.stop()
    }
}
