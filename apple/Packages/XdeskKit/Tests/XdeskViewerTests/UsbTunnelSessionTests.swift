import CryptoKit
import Foundation
import Network
import Testing
import XdeskCrypto
import XdeskTransport
import XdeskWire
@testable import XdeskViewer

/// Host thật trên loopback phục vụ cả kết nối Wi-Fi thường lẫn đường hầm USB (vai TCP đảo): ghi lại gói MediaOverTcp nhận được.
private final class TunnelFakeHost: @unchecked Sendable {
    let store: PairedDevicesStore
    let authenticator: HostAuthenticator
    let listener: ControlListener
    let identity = DeviceIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey())
    let port: UInt16
    let received = PacketBox()
    private var task: Task<Void, Never>?

    init() async throws {
        store = try PairedDevicesStore(storage: InMemoryPairedDevicesStorage(), macKey: InMemoryPairedDevicesMACKey())
        authenticator = HostAuthenticator(identity: identity, deviceName: "Fake Mac", store: store)
        await authenticator.setPairingDecider { _ in .approve(.default) }
        listener = ControlListener(security: .encrypted, authenticator: authenticator)
        port = try await listener.start(loopbackOnly: true)
        let (listener, received) = (listener, received)
        task = Task {
            for await conn in listener.connections { Task { await Self.serve(conn, received) } }
        }
    }

    private static func serve(_ conn: ControlConnection, _ received: PacketBox) async {
        let channel = PacketChannel()
        do {
            let result = try await conn.performHostHandshake(caps: [.h264, .mediaOverTcp], sessionId: "s") { hello, _ in
                if conn.isUsbTunnel {
                    await channel.set(await UdpMediaChannel.overTcp(streamId: 1, isViewer: false) { try await conn.sendMediaOverTcp($0) })
                    return DisplayReady(udpPort: 1, streamId: 1)
                }
                let udp = try await UdpMediaChannel.listen(streamId: 1, keys: await conn.udpKeys)
                await channel.set(udp)
                return DisplayReady(udpPort: await udp.localPort, streamId: 1)
            }
            await received.setNegotiated(result.caps)
            // Gửi một "khung" 4000 byte xuống viewer qua kênh media của phiên (qua TCP khi là đường hầm).
            if conn.isUsbTunnel {
                Task {
                    for n in UInt32(0)..<20 {
                        try? await channel.value?.sendFrame([0, 0, 0, 1] + [UInt8](repeating: 7, count: 4000), frameNo: n, ptsMs: n, isKeyframe: n == 0)
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
            }
            while let inbound = try await conn.nextInbound() {
                if case .mediaOverTcp(let packet) = inbound { await received.add(packet) }
            }
        } catch {
            // Viewer đóng: kết thúc phiên giả.
        }
        await channel.value?.close()
        await conn.close()
    }

    func stop() async {
        task?.cancel()
        await listener.stop()
    }
}

private actor PacketChannel {
    private(set) var value: UdpMediaChannel?
    func set(_ channel: UdpMediaChannel) { value = channel }
}

private actor PacketBox {
    private(set) var packets: [MediaPacket] = []
    private(set) var negotiated: Capabilities = []
    func add(_ packet: MediaPacket) { packets.append(packet) }
    func setNegotiated(_ caps: Capabilities) { negotiated = caps }
}

/// Viewer là TCP-server loopback (như iPhone nghe cổng USB), Mac-host nối vào như qua usbmuxd.
private final class ViewerSide: @unchecked Sendable {
    let listener: NWListener
    let port: UInt16
    let tunnels: AsyncStream<ControlConnection>
    private let queue = DispatchQueue(label: "test.usb.viewer")

    init() async throws {
        let (stream, continuation) = AsyncStream.makeStream(of: ControlConnection.self)
        tunnels = stream
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { connection in
            Task {
                if let tunnel = try? await ControlConnection.acceptUsbTunnel(connection) { continuation.yield(tunnel) }
            }
        }
        port = try await Self.ready(listener, queue: queue)
    }

    private static func ready(_ listener: NWListener, queue: DispatchQueue) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { cont in
            let done = NSLock()
            nonisolated(unsafe) var resumed = false
            listener.stateUpdateHandler = { state in
                done.lock()
                defer { done.unlock() }
                guard !resumed else { return }
                if case .ready = state, let port = listener.port?.rawValue { resumed = true; cont.resume(returning: port) }
                if case .failed(let error) = state { resumed = true; cont.resume(throwing: error) }
            }
            listener.start(queue: queue)
        }
    }

    /// Mac-host: mở TCP tới viewer và đưa cho `ControlListener` của host như một đường hầm usbmux.
    func connectHost(listener host: ControlListener, hostKey: [UInt8]) async throws {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any, using: .tcp)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            nonisolated(unsafe) var resumed = false
            let lock = NSLock()
            connection.stateUpdateHandler = { state in
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                if case .ready = state { resumed = true; cont.resume() }
                if case .failed(let error) = state { resumed = true; cont.resume(throwing: error) }
            }
            connection.start(queue: queue)
        }
        try await host.adoptUsbTunnel(connection, hostPublicKey: hostKey)
    }

    func stop() { listener.cancel() }
}

@MainActor
@Suite struct UsbTunnelSessionTests {
    private let config = DisplayConfig(w: 1280, h: 800, scale: 1, fps: 30, codec: .h264)

    private func makeTrust() throws -> ViewerTrust {
        let store = try PairedDevicesStore(storage: InMemoryPairedDevicesStorage(), macKey: InMemoryPairedDevicesMACKey())
        return ViewerTrust(identity: DeviceIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey()), knownHosts: store)
    }

    private func nextTunnel(_ side: ViewerSide) async -> ControlConnection? {
        for await tunnel in side.tunnels { return tunnel }
        return nil
    }

    /// Ghép đôi qua Wi-Fi (QR) trước: USB không ghép đôi được.
    private func pairOverWifi(_ host: TunnelFakeHost, _ trust: ViewerTrust) async throws {
        let uri = try await host.authenticator.startQrPairing(addresses: ["127.0.0.1:\(host.port)"])
        let session = ViewerSession(security: .encrypted, deviceName: "iPhone", trust: trust)
        await session.pair(with: uri, config: config)
        #expect(session.state == .streaming)
        await session.disconnect()
    }

    @Test(.timeLimit(.minutes(1))) func pairedHostStreamsOverMediaOverTcpOnlyWithIkAuthentication() async throws {
        let host = try await TunnelFakeHost()
        let trust = try makeTrust()
        try await pairOverWifi(host, trust)
        let side = try await ViewerSide()

        try await side.connectHost(listener: host.listener, hostKey: host.identity.publicKey)
        let tunnel = try #require(await nextTunnel(side))
        #expect(tunnel.isUsbTunnel)
        let session = ViewerSession(security: .encrypted, deviceName: "iPhone", trust: trust)
        await session.connect(tunnel: tunnel, config: config)
        #expect(session.state == .streaming)
        #expect(session.connectedHostId == DeviceFingerprint.make(publicKey: host.identity.publicKey))

        // Viewer → host: probe định kỳ và input đi qua kind 0x04 (không có UDP nào được mở).
        session.sendInput([.move(x: 0.5, y: 0.5)])
        var seen: Set<MediaPacketType> = []
        for _ in 0..<150 where !seen.isSuperset(of: [.probe, .input]) {
            seen = Set(await host.received.packets.map(\.header.type))
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(seen.isSuperset(of: [.probe, .input]))
        #expect(await host.received.negotiated.contains(.mediaOverTcp))
        // Host → viewer: khung video đi qua TCP, viewer ghép và đo băng thông (cửa sổ đầu của ViewerStats tính từ lúc máy khởi động nên bỏ qua).
        var kbps = 0
        for _ in 0..<200 where kbps == 0 {
            kbps = session.recvKbps
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(kbps > 0)
        await session.disconnect()
        side.stop()
        await host.stop()
    }

    @Test(.timeLimit(.minutes(1))) func hostNotPairedWithThisViewerIsRefused() async throws {
        let host = try await TunnelFakeHost()
        let side = try await ViewerSide()
        try await side.connectHost(listener: host.listener, hostKey: host.identity.publicKey)
        let tunnel = try #require(await nextTunnel(side))
        let session = ViewerSession(security: .encrypted, deviceName: "iPhone", trust: try makeTrust())
        await session.connect(tunnel: tunnel, config: config)
        #expect(session.state == .failed(TransportError.pairingRequired.localizedDescription))
        side.stop()
        await host.stop()
    }

    @Test(.timeLimit(.minutes(1))) func hostWithAKeyTheViewerNeverPairedWithIsRefusedEvenIfItClaimsAKnownOne() async throws {
        let host = try await TunnelFakeHost()
        let trust = try makeTrust()
        try await pairOverWifi(host, trust)
        let side = try await ViewerSide()
        // Kẻ giả danh khai khoá lạ trong usbHello → viewer không có khoá đó để IK.
        let stranger = DeviceIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey())
        try await side.connectHost(listener: host.listener, hostKey: stranger.publicKey)
        let tunnel = try #require(await nextTunnel(side))
        let session = ViewerSession(security: .encrypted, deviceName: "iPhone", trust: trust)
        await session.connect(tunnel: tunnel, config: config)
        #expect(session.state == .failed(TransportError.pairingRequired.localizedDescription))
        side.stop()
        await host.stop()
    }

    @Test(.timeLimit(.minutes(1))) func plaintextModeCannotUseTheTunnel() async throws {
        let side = try await ViewerSide()
        let plain = ViewerSession(security: .devPlaintext, deviceName: "iPhone")
        let host = try await TunnelFakeHost()
        try await side.connectHost(listener: host.listener, hostKey: host.identity.publicKey)
        let tunnel = try #require(await nextTunnel(side))
        await plain.connect(tunnel: tunnel, config: config)
        #expect(plain.state == .failed(TransportError.encryptionUnavailable.localizedDescription))
        side.stop()
        await host.stop()
    }
}
