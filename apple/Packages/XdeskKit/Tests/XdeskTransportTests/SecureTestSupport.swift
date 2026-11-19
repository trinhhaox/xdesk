import CryptoKit
import Foundation
import Testing
import XdeskCrypto
import XdeskWire
@testable import XdeskTransport

/// Ghi lại yêu cầu ghép đôi host nhận được và trả quyết định cấu hình sẵn.
actor PairingProbe {
    private(set) var requests: [PairingRequest] = []
    var decision: PairingDecision

    init(decision: PairingDecision = .approve(.default)) { self.decision = decision }

    func decide(_ request: PairingRequest) -> PairingDecision {
        requests.append(request)
        return decision
    }

    func setDecision(_ decision: PairingDecision) { self.decision = decision }
}

actor EventLog {
    private(set) var events: [HostAuthEvent] = []

    func start(_ stream: AsyncStream<HostAuthEvent>) -> Task<Void, Never> {
        Task { for await event in stream { events.append(event) } }
    }

    func contains(_ match: (HostAuthEvent) -> Bool) -> Bool { events.contains(where: match) }
}

struct Inbox: Sendable {
    let stream: AsyncStream<ControlConnection>

    init(_ stream: AsyncStream<ControlConnection>) { self.stream = stream }

    func next() async -> ControlConnection? {
        for await connection in stream { return connection }
        return nil
    }
}

/// Host mã hoá thật trên loopback + một danh tính viewer.
struct SecureRig {
    let hostIdentity: DeviceIdentity
    let viewerIdentity = DeviceIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey())
    let hostStore: PairedDevicesStore
    let authenticator: HostAuthenticator
    let listener: ControlListener
    let inbox: Inbox
    let probe: PairingProbe
    let log = EventLog()
    let port: UInt16

    static func make(
        store: PairedDevicesStore? = nil, decision: PairingDecision = .approve(.default),
        maxPending: Int = ControlListener.defaultMaxPending, maxPendingPerSource: Int = ControlListener.defaultMaxPendingPerSource,
        qrRotationSeconds: Double = HostAuthenticator.defaultQrRotationSeconds
    ) async throws -> SecureRig {
        let store = try store ?? PairedDevicesStore(storage: InMemoryPairedDevicesStorage(), macKey: InMemoryPairedDevicesMACKey())
        let identity = DeviceIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey())
        let authenticator = HostAuthenticator(identity: identity, deviceName: "Test Host", store: store, qrRotationSeconds: qrRotationSeconds)
        let probe = PairingProbe(decision: decision)
        await authenticator.setPairingDecider { await probe.decide($0) }
        let listener = ControlListener(
            security: .encrypted, authenticator: authenticator, maxPending: maxPending, maxPendingPerSource: maxPendingPerSource)
        let port = try await listener.start(loopbackOnly: true)
        let rig = SecureRig(
            hostIdentity: identity, hostStore: store, authenticator: authenticator, listener: listener,
            inbox: Inbox(listener.connections), probe: probe, port: port)
        _ = await rig.log.start(authenticator.events)
        return rig
    }

    private init(
        hostIdentity: DeviceIdentity, hostStore: PairedDevicesStore, authenticator: HostAuthenticator, listener: ControlListener,
        inbox: Inbox, probe: PairingProbe, port: UInt16
    ) {
        self.hostIdentity = hostIdentity
        self.hostStore = hostStore
        self.authenticator = authenticator
        self.listener = listener
        self.inbox = inbox
        self.probe = probe
        self.port = port
    }

    var hostKey: [UInt8] { hostIdentity.publicKey }

    func openViewer() async throws -> ControlConnection {
        try await ControlConnection.connect(host: "127.0.0.1", port: port, security: .encrypted)
    }

    /// Ghép đôi bằng QR thành công; trả kết nối viewer + phía host.
    func pairWithQr(name: String = "iPad") async throws -> (viewer: ControlConnection, host: ControlConnection) {
        let uri = try await authenticator.startQrPairing(addresses: ["127.0.0.1:\(port)"])
        let viewer = try await openViewer()
        _ = try await viewer.performInitiatorHandshake(identity: viewerIdentity, deviceName: name, mode: .qr(uri))
        let host = try #require(await inbox.next())
        return (viewer, host)
    }

    func reconnect() async throws -> (viewer: ControlConnection, host: ControlConnection) {
        let viewer = try await openViewer()
        _ = try await viewer.performInitiatorHandshake(identity: viewerIdentity, deviceName: "iPad", mode: .reconnect(hostKey: hostKey))
        let host = try #require(await inbox.next())
        return (viewer, host)
    }

    func stop() async { await listener.stop() }
}

/// Chờ `condition` đúng trong `seconds`; ngược lại ghi lỗi.
func eventually(seconds: Double = 5, _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}
