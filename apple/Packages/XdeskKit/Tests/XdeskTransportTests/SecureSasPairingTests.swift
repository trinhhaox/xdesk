import CryptoKit
import Foundation
import Testing
import XdeskCrypto
import XdeskWire
@testable import XdeskTransport

actor CodeBox {
    private(set) var code: String?
    func set(_ code: String) { self.code = code }
}

@Suite struct SecureSasPairingTests {
    @Test(.timeLimit(.minutes(1))) func bothScreensShowTheSameCodeAndHostApprovalPairs() async throws {
        let rig = try await SecureRig.make()
        let box = CodeBox()
        let viewer = try await rig.openViewer()
        let outcome = try await viewer.performInitiatorHandshake(
            identity: rig.viewerIdentity, deviceName: "Mac của Hào", mode: .sas(onCode: { await box.set($0) }))
        #expect(outcome.method == .sasPaired)
        #expect(outcome.hostKey == rig.hostKey)
        let request = try #require(await rig.probe.requests.first)
        guard case .sas(let hostCode) = request.method else { Issue.record("cần phương thức SAS"); return }
        #expect(await eventually { await box.code != nil })
        #expect(await box.code == hostCode)
        #expect(hostCode.count == 7)
        #expect(await rig.hostStore.devices.map(\.name) == ["Mac của Hào"])
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func rejectingOnTheHostPairsNothingAndThreeFailuresLockSasOut() async throws {
        let rig = try await SecureRig.make(decision: .reject)
        for _ in 0..<SasFailureLimiter.maxFailures {
            let viewer = try await rig.openViewer()
            await #expect(throws: TransportError.pairingDenied) {
                _ = try await viewer.performInitiatorHandshake(identity: rig.viewerIdentity, deviceName: "V", mode: .sas(onCode: { _ in }))
            }
        }
        await rig.probe.setDecision(.approve(.default))
        let viewer = try await rig.openViewer()
        await #expect(throws: (any Error).self) {
            _ = try await viewer.performInitiatorHandshake(identity: rig.viewerIdentity, deviceName: "V", mode: .sas(onCode: { _ in }))
        }
        #expect(await rig.hostStore.devices.isEmpty)
        #expect(await rig.probe.requests.count == SasFailureLimiter.maxFailures)
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func commitmentThatDoesNotMatchTheRevealedNonceIsRefused() async throws {
        let rig = try await SecureRig.make()
        let viewer = try await rig.openViewer()
        var state = try NoiseHandshakeState(pattern: .xx, role: .initiator, staticKey: rig.viewerIdentity.privateKey)
        let committedNonce = ShortAuthString.randomNonce()
        let revealedNonce = ShortAuthString.randomNonce()
        try await viewer.sendHandshake(.begin(.xx))
        let message1 = try state.writeMessage()
        guard let ephemeral = state.localEphemeralKey else { Issue.record("thiếu ephemeral"); return }
        try await viewer.sendHandshake(.commit(try ShortAuthString.commitment(
            ephemeralKey: ephemeral, staticKey: rig.viewerIdentity.publicKey, nonce: committedNonce)))
        try await viewer.sendHandshake(.noise(message1))
        _ = try state.readMessage(try await viewer.nextNoise(5))
        let hello = HandshakePayload(role: .viewer, deviceName: "Grinder", sasNonce: revealedNonce)
        try await viewer.sendHandshake(.noise(try state.writeMessage(payload: try hello.encode())))
        #expect(await eventually { (try? await viewer.nextInbound()) == nil })
        #expect(await rig.probe.requests.isEmpty)
        #expect(await rig.hostStore.devices.isEmpty)
        await rig.stop()
    }

    @Test func limiterAllowsThreeFailuresPerTenMinutes() {
        var limiter = SasFailureLimiter()
        let start = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<3 {
            #expect(limiter.allows(now: start.addingTimeInterval(Double(i))))
            limiter.recordFailure(now: start.addingTimeInterval(Double(i)))
        }
        #expect(!limiter.allows(now: start.addingTimeInterval(599)))
        #expect(limiter.allows(now: start.addingTimeInterval(601)))
    }
}
