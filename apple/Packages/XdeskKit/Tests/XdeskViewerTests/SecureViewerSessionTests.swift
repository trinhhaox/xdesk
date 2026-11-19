import CryptoKit
import Foundation
import Testing
import XdeskCrypto
import XdeskTransport
import XdeskWire
@testable import XdeskViewer

/// Host mã hoá thật trên loopback: Noise + hello/welcome + UDP mã hoá; chỉ giữ phiên mở (không có video).
private final class SecureFakeHost: @unchecked Sendable {
    let store: PairedDevicesStore
    let authenticator: HostAuthenticator
    let listener: ControlListener
    let identity = DeviceIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey())
    let port: UInt16
    private var task: Task<Void, Never>?

    init() async throws {
        store = try PairedDevicesStore(storage: InMemoryPairedDevicesStorage(), macKey: InMemoryPairedDevicesMACKey())
        authenticator = HostAuthenticator(identity: identity, deviceName: "Fake Mac", store: store)
        await authenticator.setPairingDecider { _ in .approve(.default) }
        listener = ControlListener(security: .encrypted, authenticator: authenticator)
        port = try await listener.start(loopbackOnly: true)
        let listener = listener
        task = Task {
            for await conn in listener.connections {
                Task { await Self.serve(conn) }
            }
        }
    }

    private static func serve(_ conn: ControlConnection) async {
        let box = SecureChannelBox()
        do {
            _ = try await conn.performHostHandshake(caps: [.h264], sessionId: "s") { _, _ in
                let channel = try await UdpMediaChannel.listen(streamId: 1, keys: await conn.udpKeys)
                await box.set(channel)
                return DisplayReady(udpPort: await channel.localPort, streamId: 1)
            }
            while try await conn.nextInbound() != nil {}
        } catch {
            // Viewer đóng/bị thu hồi: kết thúc phiên giả.
        }
        await box.channel?.close()
        await conn.close()
    }

    func stop() async {
        task?.cancel()
        await listener.stop()
    }
}

private actor SecureChannelBox {
    private(set) var channel: UdpMediaChannel?
    func set(_ channel: UdpMediaChannel) { self.channel = channel }
}

@MainActor
@Suite struct SecureViewerSessionTests {
    private let config = DisplayConfig(w: 1280, h: 800, scale: 1, fps: 30, codec: .h264)

    private func makeTrust() throws -> ViewerTrust {
        let store = try PairedDevicesStore(storage: InMemoryPairedDevicesStorage(), macKey: InMemoryPairedDevicesMACKey())
        return ViewerTrust(identity: DeviceIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey()), knownHosts: store)
    }

    private func waitFor(_ session: ViewerSession, seconds: Double = 5, _ match: (ViewerSession.State) -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if match(session.state) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return match(session.state)
    }

    @Test(.timeLimit(.minutes(1))) func qrPairingThenAutomaticReconnectUsesTheSavedHostKey() async throws {
        let host = try await SecureFakeHost()
        let trust = try makeTrust()
        let uri = try await host.authenticator.startQrPairing(addresses: ["127.0.0.1:\(host.port)"])

        let first = ViewerSession(security: .encrypted, deviceName: "iPhone", trust: trust)
        await first.pair(with: uri, config: config)
        #expect(first.state == .streaming)
        let known = await trust.knownHosts.devices
        #expect(known.map(\.name) == ["Fake Mac"])
        #expect(known.first?.publicKey == host.identity.publicKey)
        #expect(known.first?.lastAddress == "127.0.0.1:\(host.port)")
        await first.disconnect()

        let second = ViewerSession(security: .encrypted, deviceName: "iPhone", trust: trust)
        await second.connect(to: .manual(host: "127.0.0.1", port: host.port), config: config)
        #expect(second.state == .streaming)
        #expect(second.connectedTarget == .manual(host: "127.0.0.1", port: host.port))
        await second.disconnect()
        await host.stop()
    }

    @Test(.timeLimit(.minutes(1))) func unknownHostNeedsPairingFirst() async throws {
        let host = try await SecureFakeHost()
        let session = ViewerSession(security: .encrypted, deviceName: "iPhone", trust: try makeTrust())
        await session.connect(to: .manual(host: "127.0.0.1", port: host.port), config: config)
        #expect(session.state == .failed(TransportError.pairingRequired.localizedDescription))
        await host.stop()
    }

    @Test(.timeLimit(.minutes(1))) func revokingTheDeviceEndsTheViewerSessionQuickly() async throws {
        let host = try await SecureFakeHost()
        let trust = try makeTrust()
        let uri = try await host.authenticator.startQrPairing(addresses: ["127.0.0.1:\(host.port)"])
        let session = ViewerSession(security: .encrypted, deviceName: "iPhone", trust: trust)
        await session.pair(with: uri, config: config)
        #expect(session.state == .streaming)

        try await host.store.remove(id: trust.identity.fingerprint)
        let failed = await waitFor(session, seconds: 2) { if case .failed = $0 { true } else { false } }
        #expect(failed)
        #expect(session.state == .failed(TransportError.revokedByHost.localizedDescription))
        // Host báo thu hồi qua kênh mã hoá → viewer quên host, danh sách hiện "Chưa ghép".
        #expect(await trust.knownHosts.devices.isEmpty)
        await session.disconnect()
        #expect(session.state == .idle)

        let again = ViewerSession(security: .encrypted, deviceName: "iPhone", trust: trust)
        await again.connect(to: .manual(host: "127.0.0.1", port: host.port), config: config)
        #expect(again.state == .failed(TransportError.pairingRequired.localizedDescription))
        await host.stop()
    }

    @Test(.timeLimit(.minutes(1))) func revokedWhileOfflineReconnectIsReportedAsRefused() async throws {
        let host = try await SecureFakeHost()
        let trust = try makeTrust()
        let uri = try await host.authenticator.startQrPairing(addresses: ["127.0.0.1:\(host.port)"])
        let session = ViewerSession(security: .encrypted, deviceName: "iPhone", trust: trust)
        await session.pair(with: uri, config: config)
        await session.disconnect()

        try await host.store.remove(id: trust.identity.fingerprint)
        let retry = ViewerSession(security: .encrypted, deviceName: "iPhone", trust: trust)
        await retry.connect(to: .manual(host: "127.0.0.1", port: host.port), config: config)
        #expect(retry.state == .failed(TransportError.reconnectRefused.localizedDescription))
        #expect(retry.refusedHostId == DeviceFingerprint.make(publicKey: host.identity.publicKey))
        // Tín hiệu chưa xác thực: không tự xoá host, để người dùng quyết định ghép lại.
        #expect(await trust.knownHosts.devices.count == 1)
        await host.stop()
    }

    @Test(.timeLimit(.minutes(1))) func hostWithADifferentKeyAtTheSameAddressIsNotTrusted() async throws {
        let host = try await SecureFakeHost()
        let trust = try makeTrust()
        let uri = try await host.authenticator.startQrPairing(addresses: ["127.0.0.1:\(host.port)"])
        let session = ViewerSession(security: .encrypted, deviceName: "iPhone", trust: trust)
        await session.pair(with: uri, config: config)
        await session.disconnect()
        let saved = try #require(await trust.knownHosts.devices.first)
        // Host khác (khoá khác) nhận địa chỉ cũ: IK tới khoá đã lưu không thể hoàn tất → không kết nối được.
        let impostor = try await SecureFakeHost()
        try await trust.knownHosts.setLastAddress(id: saved.id, "127.0.0.1:\(impostor.port)")
        let retry = ViewerSession(security: .encrypted, deviceName: "iPhone", trust: trust)
        await retry.connect(to: .manual(host: "127.0.0.1", port: impostor.port), config: config)
        if case .failed = retry.state {} else { Issue.record("host mạo danh không được chấp nhận") }
        await host.stop()
        await impostor.stop()
    }
}
