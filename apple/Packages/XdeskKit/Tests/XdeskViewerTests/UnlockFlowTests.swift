import CryptoKit
import Foundation
import Testing
import XdeskCrypto
import XdeskTransport
import XdeskWire
@testable import XdeskViewer

private actor UnlockChannelBox {
    private(set) var channel: UdpMediaChannel?
    func set(_ channel: UdpMediaChannel) { self.channel = channel }
}

private func eventually(seconds: Double = 5, _ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}

private actor UnlockHostState {
    var conn: ControlConnection?
    var messages: [ControlMessage] = []
    func set(_ conn: ControlConnection) { self.conn = conn }
    func record(_ message: ControlMessage) { messages.append(message) }
    var unlockRequests: Int { messages.filter { if case .systemUnlock(let u) = $0 { u.sig == nil } else { false } }.count }
    var signatures: [String] { messages.compactMap { if case .systemUnlock(let u) = $0 { u.sig } else { nil } } }
    var keys: [UnlockKey] { messages.compactMap { if case .unlockKey(let k) = $0 { k } else { nil } } }
}

/// Host mã hoá thật trên loopback, bật `unlockAttestation`; ghi lại message của viewer và trả thử thách khi được xin.
private final class UnlockFakeHost: @unchecked Sendable {
    let state = UnlockHostState()
    let authenticator: HostAuthenticator
    let listener: ControlListener
    let identity = DeviceIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey())
    let port: UInt16
    static let nonce = [UInt8](repeating: 7, count: 32)
    private var task: Task<Void, Never>?

    init() async throws {
        let store = try PairedDevicesStore(storage: InMemoryPairedDevicesStorage(), macKey: InMemoryPairedDevicesMACKey())
        authenticator = HostAuthenticator(identity: identity, deviceName: "Fake Mac", store: store)
        await authenticator.setPairingDecider { _ in .approve(.default) }
        listener = ControlListener(security: .encrypted, authenticator: authenticator)
        port = try await listener.start(loopbackOnly: true)
        let listener = listener
        task = Task {
            for await conn in listener.connections { Task { await self.serve(conn) } }
        }
    }

    private func serve(_ conn: ControlConnection) async {
        let box = UnlockChannelBox()
        do {
            _ = try await conn.performHostHandshake(caps: [.h264, .remoteUnlock, .unlockAttestation], sessionId: "s") { _, _ in
                let ch = try await UdpMediaChannel.listen(streamId: 1, keys: await conn.udpKeys)
                await box.set(ch)
                return DisplayReady(udpPort: await ch.localPort, streamId: 1)
            }
            await state.set(conn)
            while let inbound = try await conn.nextInbound() {
                guard case .message(let envelope) = inbound else { continue }
                await state.record(envelope.message)
                if case .systemUnlock(let u) = envelope.message, u.sig == nil {
                    _ = try await conn.send(.systemUnlockChallenge(SystemUnlockChallenge(nonce: Data(Self.nonce).base64EncodedString())))
                }
            }
        } catch {}
        await box.channel?.close()
        await conn.close()
    }

    func pushUnsolicitedChallenge() async throws {
        _ = try await state.conn?.send(.systemUnlockChallenge(SystemUnlockChallenge(nonce: Data(Self.nonce).base64EncodedString())))
    }

    func stop() async { task?.cancel(); await listener.stop() }
}

private final class FakeSigner: UnlockSigner, @unchecked Sendable {
    let key = P256.Signing.PrivateKey()
    private let lock = NSLock()
    private var _hostNames: [String] = []
    var hostNames: [String] { lock.withLock { _hostNames } }
    func publicKey() async throws -> [UInt8] { Array(key.publicKey.x963Representation) }
    func existingPublicKey() async -> [UInt8]? { Array(key.publicKey.x963Representation) }
    func sign(message: [UInt8], hostName: String) async throws -> [UInt8] {
        lock.withLock { _hostNames.append(hostName) }
        return Array(try key.signature(for: message).derRepresentation)
    }
}

@MainActor
@Suite struct UnlockFlowTests {
    private let config = DisplayConfig(w: 1280, h: 800, scale: 1, fps: 30, codec: .h264)

    private func connect(signer: FakeSigner) async throws -> (UnlockHostFixture, ViewerSession, ViewerTrust) {
        let host = try await UnlockFakeHost()
        let store = try PairedDevicesStore(storage: InMemoryPairedDevicesStorage(), macKey: InMemoryPairedDevicesMACKey())
        let trust = ViewerTrust(identity: DeviceIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey()), knownHosts: store)
        let uri = try await host.authenticator.startQrPairing(addresses: ["127.0.0.1:\(host.port)"])
        let session = ViewerSession(security: .encrypted, deviceName: "iPhone", trust: trust, unlockSigner: signer)
        await session.pair(with: uri, config: config)
        #expect(session.state == .streaming)
        return (UnlockHostFixture(host: host), session, trust)
    }

    @Test(.timeLimit(.minutes(1))) func registersKeyThenSignsBoundMessageOnlyAfterUserRequest() async throws {
        let signer = FakeSigner()
        let (fixture, session, trust) = try await connect(signer: signer)
        let host = fixture.host
        #expect(await eventually { await host.state.keys.count == 1 })
        #expect(session.negotiatedCaps.contains(.unlockAttestation))

        await session.sendSystemUnlock()
        #expect(await eventually { await host.state.signatures.count == 1 })
        let sigText = try #require(await host.state.signatures.first)
        let sigData = try #require(Data(base64Encoded: sigText))
        let message = UnlockKeyFormat.signedMessage(hostKey: host.identity.publicKey, viewerKey: trust.identity.publicKey, nonce: UnlockFakeHost.nonce)
        #expect(UnlockKeyFormat.verify(publicKey: Array(signer.key.publicKey.x963Representation), message: message, derSignature: Array(sigData)))
        #expect(signer.hostNames == ["Fake Mac"])
        #expect(await host.state.keys.count == 2, "khoá được gửi lại mỗi lần bấm mở khoá")
        await session.disconnect()
        await host.stop()
    }

    @Test(.timeLimit(.minutes(1))) func unsolicitedChallengeIsDropped() async throws {
        let signer = FakeSigner()
        let (fixture, session, _) = try await connect(signer: signer)
        let host = fixture.host
        #expect(await eventually { await host.state.conn != nil })
        try await host.pushUnsolicitedChallenge()
        try await Task.sleep(for: .milliseconds(500))
        #expect(await host.state.signatures.isEmpty)
        #expect(signer.hostNames.isEmpty)

        // Một yêu cầu → đúng một lần ký; thử thách thứ hai ngay sau đó bị bỏ.
        await session.sendSystemUnlock()
        #expect(await eventually { await host.state.signatures.count == 1 })
        try await host.pushUnsolicitedChallenge()
        try await Task.sleep(for: .milliseconds(500))
        #expect(await host.state.signatures.count == 1)
        await session.disconnect()
        await host.stop()
    }

    @Test func requestGateExpiresAndIsSingleUse() {
        var gate = UnlockRequestGate()
        let t0 = Date(timeIntervalSince1970: 1000)
        let unarmed = gate.consume(now: t0)
        gate.arm(now: t0)
        let first = gate.consume(now: t0.addingTimeInterval(5))
        let second = gate.consume(now: t0.addingTimeInterval(6))
        gate.arm(now: t0)
        let expired = gate.consume(now: t0.addingTimeInterval(UnlockRequestGate.window + 1))
        #expect(!unarmed && first && !second && !expired)
    }
}

/// Gói host để truyền qua `connect` mà không cần `Sendable` thủ công trong tuple.
private struct UnlockHostFixture { let host: UnlockFakeHost }
