import CryptoKit
import Foundation
import Testing
import XdeskCrypto
import XdeskWire
@testable import XdeskTransport

@Suite struct SecureReconnectTests {
    @Test(.timeLimit(.minutes(1))) func pairedViewerReconnectsWithIkAndGetsStoredPermissions() async throws {
        let rig = try await SecureRig.make()
        let (firstViewer, firstHost) = try await rig.pairWithQr()
        await firstViewer.close()
        await firstHost.close()

        let (viewer, host) = try await rig.reconnect()
        try await viewer.send(.ping(Ping(t0: 1)), id: 3)
        #expect(try await host.nextInbound() == .message(ControlEnvelope(id: 3, message: .ping(Ping(t0: 1)))))
        let peer = await host.peer
        #expect(peer?.method == .reconnect)
        #expect(peer?.permissions == .default)
        #expect(peer?.deviceId == rig.viewerIdentity.fingerprint)
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func unknownKeyGetsNoAnswerAtAll() async throws {
        let rig = try await SecureRig.make()
        let stranger = DeviceIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey())
        let viewer = try await rig.openViewer()
        await #expect(throws: (any Error).self) {
            _ = try await viewer.performInitiatorHandshake(identity: stranger, deviceName: "Stranger", mode: .reconnect(hostKey: rig.hostKey))
        }
        #expect(await rig.hostStore.devices.isEmpty)
        #expect(await rig.listener.activeViewers == 0)
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func ikIsAuthenticatedOnlyAfterTheFirstValidEncryptedFrame() async throws {
        let rig = try await SecureRig.make()
        let (firstViewer, firstHost) = try await rig.pairWithQr()
        await firstViewer.close()
        await firstHost.close()
        let id = rig.viewerIdentity.fingerprint
        // pairWithQr đã markSeen; đặt lại mốc để thấy rõ chỉ frame hợp lệ mới cập nhật.
        let before = try #require(await rig.hostStore.devices.first?.lastSeen)

        let viewer = try await rig.openViewer()
        var state = try NoiseHandshakeState(pattern: .ik, role: .initiator, staticKey: rig.viewerIdentity.privateKey, remoteStaticKey: rig.hostKey)
        try await viewer.sendHandshake(.begin(.ik))
        try await viewer.sendHandshake(.noise(try state.writeMessage(payload: try HandshakePayload(role: .viewer, deviceName: "iPad").encode())))
        _ = try state.readMessage(try await viewer.nextNoise(5))
        let host = try #require(await rig.inbox.next())
        try await Task.sleep(for: .milliseconds(300))
        #expect(await rig.hostStore.devices.first?.lastSeen == before)      // msg1 hợp lệ nhưng chưa có frame mã hoá nào
        #expect(await rig.listener.activeViewers == 0)                       // chưa giữ chỗ viewer, vẫn trong hàng chờ chưa xác thực
        #expect(await rig.listener.pendingHandshakes == 1)
        #expect(!(await rig.log.contains { if case .sessionOpened(let p) = $0 { p.deviceId == id && p.method == .reconnect } else { false } }))

        await viewer.installSession(keys: try state.sessionKeys())
        try await viewer.send(.ping(Ping(t0: 9)))
        _ = try await host.nextInbound()
        #expect(await eventually { await rig.listener.activeViewers == 1 })
        #expect(await eventually { await rig.log.contains { if case .sessionOpened(let p) = $0 { p.method == .reconnect } else { false } } })
        #expect(await eventually { (await rig.hostStore.devices.first?.lastSeen ?? before) > before })
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func revokingADeviceClosesItsLiveSessionQuickly() async throws {
        let rig = try await SecureRig.make()
        let (viewer, host) = try await rig.pairWithQr()
        _ = try await viewer.send(.ping(Ping(t0: 1)))
        _ = try await host.nextInbound()
        let started = ContinuousClock.now
        try await rig.hostStore.remove(id: rig.viewerIdentity.fingerprint)
        #expect(await eventually(seconds: 1) { await host.isClosed })
        #expect(ContinuousClock.now - started < .seconds(1))
        _ = try? await viewer.nextInbound()
        #expect(await rig.log.contains { if case .sessionRevoked = $0 { true } else { false } })

        let again = try await rig.openViewer()
        await #expect(throws: (any Error).self) {
            _ = try await again.performInitiatorHandshake(
                identity: rig.viewerIdentity, deviceName: "iPad", mode: .reconnect(hostKey: rig.hostKey))
        }
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func tcpRekeyKeepsTheStreamInSync() async throws {
        let rig = try await SecureRig.make()
        let (viewer, host) = try await rig.pairWithQr()
        await viewer.setRekeyInterval(.zero)
        await host.setRekeyInterval(.zero)
        for i in 0..<5 {
            try await viewer.send(.ping(Ping(t0: Int64(i))), id: UInt32(i))
            #expect(try await host.nextInbound() == .message(ControlEnvelope(id: UInt32(i), message: .ping(Ping(t0: Int64(i))))))
            try await host.send(.pong(Pong(t0: Int64(i), t1: 1, t2: 2)), id: UInt32(i))
            #expect(try await viewer.nextInbound() == .message(ControlEnvelope(id: UInt32(i), message: .pong(Pong(t0: Int64(i), t1: 1, t2: 2)))))
        }
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func plaintextFramesAreRefusedOnAnEncryptedConnection() async throws {
        let rig = try await SecureRig.make()
        let viewer = try await rig.openViewer()
        // Gửi thẳng frame control rõ trước khi bắt tay: host phải đóng, không trả lời.
        let bytes = try ControlFrameCodec.encode(ControlFrame(kind: .control, payload: Array("{}".utf8)))
        await viewer.writeRaw(bytes)
        #expect(await eventually { (try? await viewer.nextInbound()) == nil })
        #expect(await rig.listener.activeViewers == 0)
        await rig.stop()
    }
}

extension ControlConnection {
    /// Chỉ cho test: ghi byte thô, bỏ qua cipher.
    func writeRaw(_ bytes: [UInt8]) async { try? await write(bytes) }
}
