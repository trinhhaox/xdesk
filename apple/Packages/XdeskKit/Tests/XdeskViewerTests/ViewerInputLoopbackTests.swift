#if DEBUG
import Foundation
import Testing
import XdeskInput
import XdeskTransport
import XdeskWire
@testable import XdeskViewer

/// Host giả trên loopback: bắt tay thật, UDP thật; giải mã gói input bằng `InputReceiver` và trả input-ack.
private final class FakeHost: @unchecked Sendable {
    let listener = ControlListener(security: .devPlaintext)
    let port: UInt16
    let received = Received()
    private var task: Task<Void, Never>?

    actor Received {
        var events: [InputEvent] = []
        var texts: [String] = []
        var packetsSeen = 0
        func add(_ e: [InputEvent]) { events += e; packetsSeen += 1 }
        func add(text: String) { texts.append(text) }
    }

    init() async throws { port = try await listener.start(loopbackOnly: true) }

    func run(dropFirstAcks: Int = 0) {
        let received = received
        task = Task { [listener] in
            for await conn in listener.connections {
                guard let channel = try? await Self.handshake(conn) else { return }
                async let control: Void = Self.readText(conn, received)
                await Self.serve(channel, received, dropFirstAcks: dropFirstAcks)
                await control
                return
            }
        }
    }

    private static func handshake(_ conn: ControlConnection) async throws -> UdpMediaChannel {
        let box = ChannelBox()
        _ = try await conn.performHostHandshake(caps: [.h264], sessionId: "s") { _, _ in
            let channel = try await UdpMediaChannel.listen(streamId: 1)
            await box.set(channel)
            return DisplayReady(udpPort: await channel.localPort, streamId: 1)
        }
        guard let channel = await box.channel else { throw TransportError.noPeer }
        return channel
    }

    private static func readText(_ conn: ControlConnection, _ received: Received) async {
        while let inbound = try? await conn.nextInbound() {
            if case .message(let envelope) = inbound, case .inputText(let t) = envelope.message { await received.add(text: t.text) }
        }
    }

    private static func serve(_ channel: UdpMediaChannel, _ received: Received, dropFirstAcks: Int) async {
        var receiver = InputReceiver()
        var dropped = 0
        for await event in channel.events {
            guard case .packet(let packet) = event, packet.header.type == .input,
                  let events = try? InputEvent.decodeBatch(packet.payload) else { continue }
            await received.add(receiver.accept(events, nowMs: Int64(ProcessInfo.processInfo.systemUptime * 1000)))
            if dropped < dropFirstAcks { dropped += 1; continue }
            try? await channel.sendPacket(.inputAck(streamId: 1, ack: InputAck(seq: receiver.ackSeq)))
        }
    }

    func stop() async { task?.cancel(); await listener.stop() }
}

private actor ChannelBox {
    var channel: UdpMediaChannel?
    func set(_ c: UdpMediaChannel) { channel = c }
}

@MainActor
@Suite struct ViewerInputLoopbackTests {
    private func connect(_ host: FakeHost) async throws -> ViewerSession {
        let session = ViewerSession(security: .devPlaintext, deviceName: "Test")
        await session.connect(to: .manual(host: "127.0.0.1", port: host.port), config: DisplayConfig(w: 1920, h: 1200, scale: 2, fps: 60, codec: .h264))
        try #require(session.state == .streaming)
        return session
    }

    private func waitFor(_ condition: @escaping () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return false
    }

    @Test(.timeLimit(.minutes(1))) func eventsArriveInOrderAndAreAcked() async throws {
        let host = try await FakeHost()
        host.run()
        let session = try await connect(host)
        let sent: [InputEvent] = [
            .move(x: 0.25, y: 0.75), .button(down: true, x: 0.25, y: 0.75), .button(down: false, x: 0.25, y: 0.75),
            .key(usage: 0x04, down: true, mods: .command), .key(usage: 0x04, down: false),
        ]
        // Gói đầu tiên có thể đi trước khi host biết địa chỉ viewer; sendInput gửi lại tới khi được ack.
        session.sendInput(sent)
        let received = host.received
        #expect(await waitFor { await received.events.count >= sent.count })
        #expect(await received.events.map(\.kind) == sent.map(\.kind))
        #expect(await received.events.map(\.seq) == [0, 1, 2, 3, 4])
        #expect(await received.events[3].mods == InputModifiers.command.rawValue)
        #expect(await waitFor { session.inputSequencer.pendingCount == 0 })
        await session.disconnect()
        await host.stop()
    }

    @Test(.timeLimit(.minutes(1))) func lostAckTriggersResendWithoutDuplicateDelivery() async throws {
        let host = try await FakeHost()
        host.run(dropFirstAcks: 2)
        let session = try await connect(host)
        session.sendInput([.button(down: true, x: 0.5, y: 0.5), .button(down: false, x: 0.5, y: 0.5)])
        let received = host.received
        #expect(await waitFor { session.inputSequencer.pendingCount == 0 })
        #expect(await received.packetsSeen >= 2)
        #expect(await received.events.filter(\.isReliable).map(\.seq) == [1, 2])
        await session.disconnect()
        await host.stop()
    }

    @Test(.timeLimit(.minutes(1))) func textGoesOverControlChannel() async throws {
        let host = try await FakeHost()
        host.run()
        let session = try await connect(host)
        #expect(await session.sendText("Tiếng Việt có dấu"))
        let received = host.received
        #expect(await waitFor { await received.texts == ["Tiếng Việt có dấu"] })
        await session.disconnect()
        #expect(await session.sendText("x") == false)
        await host.stop()
    }

    @Test func inputIsIgnoredWhenNotStreaming() async throws {
        let session = ViewerSession(security: .devPlaintext, deviceName: "Test")
        session.sendInput([.button(down: true, x: 0.5, y: 0.5)])
        #expect(session.inputSequencer.pendingCount == 0)
    }
}
#endif
