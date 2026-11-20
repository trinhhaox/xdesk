import CryptoKit
import Foundation
import Testing
import XdeskCrypto
import XdeskWire
@testable import XdeskTransport

actor CodeBox {
    private(set) var prompt: SasPrompt?
    var code: String? { prompt?.code }
    func set(_ prompt: SasPrompt) { self.prompt = prompt }
}

actor DoneFlag {
    private(set) var done = false
    func mark() { done = true }
}

@Suite struct SecureSasPairingTests {
    @Test(.timeLimit(.minutes(1))) func bothScreensShowTheSameCodeAndHostApprovalPairs() async throws {
        let rig = try await SecureRig.make()
        let box = CodeBox()
        let viewer = try await rig.openViewer()
        let outcome = try await viewer.performInitiatorHandshake(
            identity: rig.viewerIdentity, deviceName: "Mac của Hào", mode: .sas(onCode: { await box.set($0); $0.answer(true) }))
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

    @Test(.timeLimit(.minutes(1))) func viewerWaitsForItsOwnConfirmationEvenAfterTheHostAccepts() async throws {
        let rig = try await SecureRig.make()
        let box = CodeBox()
        let done = DoneFlag()
        let viewer = try await rig.openViewer()
        let handshake = Task {
            let outcome = try await viewer.performInitiatorHandshake(
                identity: rig.viewerIdentity, deviceName: "V", mode: .sas(onCode: { await box.set($0) }))
            await done.mark()
            return outcome
        }
        #expect(await eventually { await !rig.hostStore.devices.isEmpty })
        try await Task.sleep(for: .milliseconds(300))
        #expect(await !done.done, "host đồng ý thôi chưa đủ: viewer phải tự xác nhận")
        let prompt = try #require(await box.prompt)
        prompt.answer(true)
        #expect(try await handshake.value.method == .sasPaired)
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func mismatchOnTheViewerAbortsEvenThoughTheHostAccepted() async throws {
        let rig = try await SecureRig.make()
        let viewer = try await rig.openViewer()
        await #expect(throws: TransportError.pairingDenied) {
            _ = try await viewer.performInitiatorHandshake(
                identity: rig.viewerIdentity, deviceName: "V", mode: .sas(onCode: { $0.answer(false) }))
        }
        #expect(await eventually { (try? await viewer.nextInbound()) == nil })
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func closingTheConnectionWhileWaitingReleasesThePromptAtOnce() async throws {
        let rig = try await SecureRig.make()
        let box = CodeBox()
        let viewer = try await rig.openViewer()
        let handshake = Task {
            try await viewer.performInitiatorHandshake(
                identity: rig.viewerIdentity, deviceName: "V", mode: .sas(onCode: { await box.set($0) }))
        }
        #expect(await eventually { await !rig.hostStore.devices.isEmpty })
        #expect(await eventually { await box.prompt != nil })
        await viewer.close()
        await #expect(throws: TransportError.pairingDenied) { _ = try await handshake.value }
        #expect(await box.prompt?.isPending == false, "UI không được hiện lại prompt đã bỏ")
        await rig.stop()
    }

    @Test func promptKeepsTheFirstAnswerAndTimesOutAsMismatch() async {
        let mismatches = DoneFlag()
        let prompt = SasPrompt(code: "123 456") { Task { await mismatches.mark() } }
        prompt.answer(true)
        prompt.answer(false)
        #expect(await prompt.decision(timeoutSeconds: 5))
        #expect(await !mismatches.done)
        #expect(await !SasPrompt(code: "000 000").decision(timeoutSeconds: 0.05))
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
