#if DEBUG
import Testing
import XdeskWire
@testable import XdeskTransport

@Suite struct ControlHandshakeTests {
    @Test(.timeLimit(.minutes(1))) func helloToDisplayReadyOverLoopback() async throws {
        let pair = try await makeControlPair(streamId: 7)
        #expect(pair.host.peer.name == "Test Viewer")
        #expect(pair.host.display == testDisplay)
        #expect(pair.host.caps == [.h264])               // giao của host {h264, mediaOverTcp} và viewer {h264, hevc}
        #expect(pair.viewerResult.sessionId == "s-test")
        #expect(pair.viewerResult.ready.streamId == 7)
        #expect(pair.viewerResult.ready.udpPort != 0)
        await pair.viewer.close()
        await pair.hostConnection.close()
        await pair.hostChannel.close()
        await pair.listener.stop()
    }

    @Test(.timeLimit(.minutes(1))) func controlMessagesFlowAfterHandshake() async throws {
        let pair = try await makeControlPair()
        try await pair.viewer.send(.keyframeRequest(KeyframeRequest(streamId: 7)), id: 99)
        let inbound = try await pair.hostConnection.nextInbound()
        #expect(inbound == .message(ControlEnvelope(id: 99, message: .keyframeRequest(KeyframeRequest(streamId: 7)))))
        await pair.viewer.close()
        let afterClose = try await pair.hostConnection.nextInbound()
        #expect(afterClose == nil)   // EOF sạch
        await pair.hostChannel.close()
        await pair.listener.stop()
    }

    @Test(.timeLimit(.minutes(1))) func majorVersionMismatchIsRejected() async throws {
        let listener = ControlListener(security: testSecurity)
        let port = try await listener.start(loopbackOnly: true)
        let hostSide = Task { () -> Bool in
            for await conn in listener.connections {
                do {
                    _ = try await conn.performHostHandshake(caps: [.h264], sessionId: "x") { _, _ in DisplayReady(udpPort: 1, streamId: 1) }
                    return false
                } catch TransportError.rejected(let reason, _) { return reason == Reject.reasonVersion }
            }
            return false
        }
        let viewer = try await ControlConnection.connect(host: "127.0.0.1", port: port, security: testSecurity)
        try await viewer.send(.hello(Hello(ver: "2.0", caps: 1, name: "future")))
        guard case .message(let envelope)? = try await viewer.nextInbound(), case .reject(let r) = envelope.message else {
            Issue.record("expected reject"); return
        }
        #expect(r.reason == Reject.reasonVersion)
        let hostRejected = try await hostSide.value
        #expect(hostRejected)
        await viewer.close()
        await listener.stop()
    }

    @Test(.timeLimit(.minutes(1))) func fifthViewerIsToldBusy() async throws {
        let listener = ControlListener(security: testSecurity)
        let port = try await listener.start(loopbackOnly: true)
        var accepted: [ControlConnection] = []
        for _ in 0..<ControlListener.defaultMaxViewers {
            accepted.append(try await ControlConnection.connect(host: "127.0.0.1", port: port, security: testSecurity))
        }
        // Chờ listener ghi nhận đủ 4 kết nối trước khi thử kết nối thứ 5.
        var spins = 0
        while await listener.activeViewers < ControlListener.defaultMaxViewers, spins < 200 {
            try await Task.sleep(for: .milliseconds(25)); spins += 1
        }
        #expect(await listener.activeViewers == ControlListener.defaultMaxViewers)
        let fifth = try await ControlConnection.connect(host: "127.0.0.1", port: port, security: testSecurity)
        guard case .message(let envelope)? = try await fifth.nextInbound(), case .reject(let r) = envelope.message else {
            Issue.record("expected busy reject"); return
        }
        #expect(r.reason == ControlListener.busyReason)
        for c in accepted { await c.close() }
        await fifth.close()
        await listener.stop()
    }

    @Test func encryptedListenerWithoutAuthenticatorRefusesToStart() async {
        let listener = ControlListener(security: .encrypted)
        await #expect(throws: TransportError.encryptionUnavailable) {
            _ = try await listener.start(loopbackOnly: true)
        }
    }

    @Test func connectionFailureIsTyped() async {
        await #expect(throws: TransportError.self) {
            _ = try await ControlConnection.connect(host: "127.0.0.1", port: 1, security: testSecurity, timeoutSeconds: 2)
        }
    }
}
#endif
