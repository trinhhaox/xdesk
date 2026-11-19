import CryptoKit
import Foundation
import Testing
import XdeskCrypto
import XdeskWire
@testable import XdeskTransport

@Suite struct SecureQrPairingTests {
    @Test(.timeLimit(.minutes(1))) func qrPairingStoresDeviceThenStreamsOverEncryptedControl() async throws {
        let rig = try await SecureRig.make()
        let (viewer, host) = try await rig.pairWithQr()
        try await viewer.send(.ping(Ping(t0: 42)), id: 7)
        #expect(try await host.nextInbound() == .message(ControlEnvelope(id: 7, message: .ping(Ping(t0: 42)))))
        try await host.send(.pong(Pong(t0: 42, t1: 43, t2: 44)), id: 7)
        #expect(try await viewer.nextInbound() == .message(ControlEnvelope(id: 7, message: .pong(Pong(t0: 42, t1: 43, t2: 44)))))

        let devices = await rig.hostStore.devices
        #expect(devices.map(\.name) == ["iPad"])
        #expect(devices.first?.publicKey == rig.viewerIdentity.publicKey)
        #expect(devices.first?.permissions == .default)
        let request = await rig.probe.requests.first
        #expect(request?.method == .qr)
        #expect(request?.deviceId == rig.viewerIdentity.fingerprint)
        #expect(await rig.log.contains { if case .qrClosed(.paired) = $0 { true } else { false } })
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func tokenIsSingleUse() async throws {
        let rig = try await SecureRig.make()
        let uri = try await rig.authenticator.startQrPairing(addresses: ["127.0.0.1:\(rig.port)"])
        let first = try await rig.openViewer()
        _ = try await first.performInitiatorHandshake(identity: rig.viewerIdentity, deviceName: "A", mode: .qr(uri))
        let again = try await rig.openViewer()
        await #expect(throws: (any Error).self) {
            _ = try await again.performInitiatorHandshake(
                identity: DeviceIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey()), deviceName: "B", mode: .qr(uri))
        }
        #expect(await rig.hostStore.devices.map(\.name) == ["A"])
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func wrongTokenIsRejectedAndFiveFailuresCloseTheQr() async throws {
        let rig = try await SecureRig.make()
        let real = try await rig.authenticator.startQrPairing(addresses: ["127.0.0.1:\(rig.port)"])
        let forged = try PairingURI(hostPublicKey: real.hostPublicKey, token: Array(repeating: 9, count: 32), addresses: real.addresses)
        for _ in 0..<PairingTokenIssuer.maxFailures {
            let viewer = try await rig.openViewer()
            await #expect(throws: (any Error).self) {
                _ = try await viewer.performInitiatorHandshake(identity: rig.viewerIdentity, deviceName: "X", mode: .qr(forged))
            }
        }
        #expect(await eventually { await rig.log.contains { if case .qrClosed(.tooManyFailures) = $0 { true } else { false } } })
        // Token thật cũng bị vô hiệu sau 5 lần hỏng.
        let viewer = try await rig.openViewer()
        await #expect(throws: (any Error).self) {
            _ = try await viewer.performInitiatorHandshake(identity: rig.viewerIdentity, deviceName: "Y", mode: .qr(real))
        }
        #expect(await rig.hostStore.devices.isEmpty)
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func noOpenQrMeansNoPairing() async throws {
        let rig = try await SecureRig.make()
        let uri = try await rig.authenticator.startQrPairing(addresses: ["127.0.0.1:\(rig.port)"])
        await rig.authenticator.stopQrPairing()
        let viewer = try await rig.openViewer()
        await #expect(throws: (any Error).self) {
            _ = try await viewer.performInitiatorHandshake(identity: rig.viewerIdentity, deviceName: "Late", mode: .qr(uri))
        }
        #expect(await rig.hostStore.devices.isEmpty)
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func viewerPinsHostKeyBeforeSendingItsIdentity() async throws {
        let rig = try await SecureRig.make()
        let real = try await rig.authenticator.startQrPairing(addresses: ["127.0.0.1:\(rig.port)"])
        let impostor = DeviceIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey())
        let wrongKey = try PairingURI(hostPublicKey: impostor.publicKey, token: real.token, addresses: real.addresses)
        let viewer = try await rig.openViewer()
        await #expect(throws: TransportError.hostKeyMismatch) {
            _ = try await viewer.performInitiatorHandshake(identity: rig.viewerIdentity, deviceName: "V", mode: .qr(wrongKey))
        }
        #expect(await rig.hostStore.devices.isEmpty)
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func hostRefusalPairsNothing() async throws {
        let rig = try await SecureRig.make(decision: .reject)
        let uri = try await rig.authenticator.startQrPairing(addresses: ["127.0.0.1:\(rig.port)"])
        let viewer = try await rig.openViewer()
        await #expect(throws: TransportError.pairingDenied) {
            _ = try await viewer.performInitiatorHandshake(identity: rig.viewerIdentity, deviceName: "Nope", mode: .qr(uri))
        }
        #expect(await rig.hostStore.devices.isEmpty)
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func approvedPermissionsAreStored() async throws {
        let viewOnly = DevicePermissions(view: true, input: false, clipboard: false, audio: false)
        let rig = try await SecureRig.make(decision: .approve(viewOnly))
        _ = try await rig.pairWithQr()
        #expect(await rig.hostStore.devices.first?.permissions == viewOnly)
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func qrRotatesWhileASessionIsActive() async throws {
        let rig = try await SecureRig.make(qrRotationSeconds: 1)
        _ = try await rig.pairWithQr()   // phiên đang chạy
        let first = try await rig.authenticator.startQrPairing(addresses: ["127.0.0.1:\(rig.port)"])
        let rotated = await eventually(seconds: 6) {
            await rig.log.events.contains { if case .qrIssued(let uri) = $0 { uri.token != first.token } else { false } }
        }
        #expect(rotated)
        await rig.stop()
    }
}
