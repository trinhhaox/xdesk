import CryptoKit
import Foundation
import Testing
import XdeskCrypto
import XdeskTransport
import XdeskWire
@testable import XdeskViewer

@MainActor private func waitUntil(seconds: Double = 5, _ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}

/// Host mã hoá thật trên loopback; sau handshake gửi `host.state` theo yêu cầu của test và không phát khung hình nào.
private final class StateFakeHost: @unchecked Sendable {
    let authenticator: HostAuthenticator
    let listener: ControlListener
    let identity = DeviceIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey())
    let port: UInt16
    let connBox = ConnBox()
    private var task: Task<Void, Never>?

    actor ChannelBox {
        var channel: UdpMediaChannel?
        func set(_ channel: UdpMediaChannel) { self.channel = channel }
    }

    actor ConnBox {
        var conn: ControlConnection?
        func set(_ conn: ControlConnection) { self.conn = conn }
    }

    init() async throws {
        let store = try PairedDevicesStore(storage: InMemoryPairedDevicesStorage(), macKey: InMemoryPairedDevicesMACKey())
        authenticator = HostAuthenticator(identity: identity, deviceName: "Fake Mac", store: store)
        await authenticator.setPairingDecider { _ in .approve(.default) }
        listener = ControlListener(security: .encrypted, authenticator: authenticator)
        port = try await listener.start(loopbackOnly: true)
        let listener = listener
        task = Task { for await conn in listener.connections { Task { await self.serve(conn) } } }
    }

    private func serve(_ conn: ControlConnection) async {
        let channelBox = ChannelBox()
        do {
            _ = try await conn.performHostHandshake(caps: [.h264], sessionId: "s") { _, _ in
                let ch = try await UdpMediaChannel.listen(streamId: 1, keys: await conn.udpKeys)
                await channelBox.set(ch)
                return DisplayReady(udpPort: await ch.localPort, streamId: 1)
            }
            await connBox.set(conn)
            while try await conn.nextInbound() != nil {}
        } catch {}
        await channelBox.channel?.close()
        await conn.close()
    }

    func send(_ state: HostState) async throws {
        _ = try await connBox.conn?.send(.hostState(state))
    }

    func stop() async { task?.cancel(); await listener.stop() }
}

@MainActor
@Suite struct HostStateTests {
    private let config = DisplayConfig(w: 1280, h: 800, scale: 1, fps: 30, codec: .h264)

    @Test(.timeLimit(.minutes(1))) func videoUnavailableKeepsTheSessionStreamingAndRecovers() async throws {
        let host = try await StateFakeHost()
        let store = try PairedDevicesStore(storage: InMemoryPairedDevicesStorage(), macKey: InMemoryPairedDevicesMACKey())
        let trust = ViewerTrust(identity: DeviceIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey()), knownHosts: store)
        let uri = try await host.authenticator.startQrPairing(addresses: ["127.0.0.1:\(host.port)"])
        let session = ViewerSession(security: .encrypted, deviceName: "iPhone", trust: trust)
        await session.pair(with: uri, config: config)
        #expect(session.state == .streaming)
        #expect(session.hostState == nil)
        #expect(!session.hostVideoUnavailable)
        #expect(await waitUntil { await host.connBox.conn != nil })

        try await host.send(HostState(videoAvailable: false, locked: true))
        #expect(await waitUntil { session.hostVideoUnavailable })
        #expect(session.hostState?.locked == true)
        // Không có khung hình nào đến vẫn không rớt phiên.
        try await Task.sleep(for: .milliseconds(400))
        #expect(session.state == .streaming)

        try await host.send(HostState(videoAvailable: true, locked: false))
        #expect(await waitUntil { !session.hostVideoUnavailable })
        await session.disconnect()
        #expect(session.hostState == nil)
        await host.stop()
    }
}
