import Foundation
import XdeskCrypto
import XdeskTransport
import XdeskWire

extension ViewerSession {
    /// Viewer là TCP-server (iPhone/iPad): Mac nối vào qua usbmuxd. Noise vẫn do viewer khởi xướng (IK với khoá host đã ghép) —
    /// chặt như Wi-Fi: host lạ → `pairingRequired` (ghép đôi phải làm qua Wi-Fi/QR trước), không có đường tắt cho plaintext.
    public func connect(tunnel: ControlConnection, config: DisplayConfig) async {
        guard state == .idle || isFailed else { await tunnel.close(); return }
        setState(.connecting)
        refusedHostId = nil
        connectedHostId = nil
        connectedHostKey = nil
        connectedHostName = nil
        unlockGate.reset()
        connectedRemoteAddress = nil
        connectedTarget = nil
        do {
            try await establishTunnel(tunnel, config: config)
            setState(.streaming)
        } catch {
            log.error("usb connect failed: \(error.localizedDescription, privacy: .public)")
            await teardown()
            await tunnel.close()
            setState(.failed(error.localizedDescription))
        }
    }

    private func establishTunnel(_ conn: ControlConnection, config: DisplayConfig) async throws {
        guard security == .encrypted, let trust else { throw TransportError.encryptionUnavailable }
        connection = conn
        let hint = try await conn.receiveUsbHello()
        let known = await trust.knownHosts.devices.filter { $0.role == .host }
        guard let host = known.first(where: { $0.publicKey == hint }) else { throw TransportError.pairingRequired }
        let outcome: InitiatorOutcome
        do {
            outcome = try await conn.performInitiatorHandshake(
                identity: trust.identity, deviceName: deviceName, mode: .reconnect(hostKey: host.publicKey))
        } catch TransportError.connectionClosed {
            refusedHostId = host.id
            throw TransportError.reconnectRefused
        }
        await remember(outcome, target: nil, trust: trust)
        connectedHostId = host.id
        connectedHostKey = host.publicKey
        connectedHostName = host.name
        try await finishEstablishing(conn, config: config, target: nil)
    }
}
