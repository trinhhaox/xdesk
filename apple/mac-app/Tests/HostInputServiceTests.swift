import CoreGraphics
import Testing
import XdeskInput
import XdeskWire
@testable import Xdesk

@Suite struct HostInputServiceTests {
    private let rect = CGRect(x: -1000, y: 0, width: 1000, height: 500)

    private func makeService(_ fake: FakeEventInjector, trusted: Bool = true) -> HostInputService {
        HostInputService(streamId: 1, mapper: CoordinateMapper(bounds: { rect }), injector: fake, isTrusted: { trusted })
    }

    private func packet(_ events: [InputEvent]) throws -> MediaPacket { try .input(streamId: 1, events: events) }

    private func reliable(_ events: [InputEvent]) -> [InputEvent] {
        var seq: UInt32 = 0
        return events.map { var e = $0; if e.isReliable { seq += 1; e.seq = seq }; return e }
    }

    @Test func clickMapsToNegativeOriginAndAcks() async throws {
        let fake = FakeEventInjector()
        let service = makeService(fake)
        let events = reliable([.move(x: 0.5, y: 0.5), .button(down: true, x: 0.5, y: 0.5), .button(down: false, x: 0.5, y: 0.5)])
        let ack = await service.handle(try packet(events), nowMs: 0)
        let p = CGPoint(x: -500, y: 250)
        #expect(fake.calls == [.move(p, held: nil), .button(.left, down: true, p, clicks: 1), .button(.left, down: false, p, clicks: 1)])
        #expect(ack == .inputAck(streamId: 1, ack: InputAck(seq: 2)))
    }

    @Test func moveWhileButtonHeldIsDrag() async throws {
        let fake = FakeEventInjector()
        let service = makeService(fake)
        _ = await service.handle(try packet(reliable([.button(down: true, x: 0, y: 0), .move(x: 1, y: 0)])), nowMs: 0)
        #expect(fake.calls[1] == .move(CGPoint(x: -0.5, y: 0), held: .left))
    }

    @Test func keysUseHidMapAndModifiers() async throws {
        let fake = FakeEventInjector()
        let service = makeService(fake)
        let events = reliable([.key(usage: 0x04, down: true, mods: .command), .key(usage: 0x04, down: false), .key(usage: 0x46, down: true)])
        _ = await service.handle(try packet(events), nowMs: 0)
        #expect(fake.calls == [.key(0, down: true, flags: .maskCommand), .key(0, down: false, flags: [])])
    }

    @Test func scrollAndHeartbeat() async throws {
        let fake = FakeEventInjector()
        let service = makeService(fake)
        let ack = await service.handle(try packet([.scroll(dx: 3.4, dy: -20), .heartbeat]), nowMs: 0)
        #expect(fake.calls == [.scroll(3, -20)])
        #expect(ack == nil)
    }

    @Test func duplicateAndOutOfOrderEventsAreNotReapplied() async throws {
        let fake = FakeEventInjector()
        let service = makeService(fake)
        let events = reliable([.button(down: true, x: 0, y: 0), .button(down: false, x: 0, y: 0)])
        _ = await service.handle(try packet([events[1]]), nowMs: 0)
        #expect(fake.calls.isEmpty)
        _ = await service.handle(try packet([events[0]]), nowMs: 10)
        #expect(fake.calls.count == 2)
        let ack = await service.handle(try packet(events), nowMs: 20)
        #expect(fake.calls.count == 2)
        #expect(ack == .inputAck(streamId: 1, ack: InputAck(seq: 2)))
    }

    @Test func withoutAccessibilityNothingIsInjectedButAckStopsResends() async throws {
        let fake = FakeEventInjector()
        let service = makeService(fake, trusted: false)
        let ack = await service.handle(try packet(reliable([.button(down: true, x: 0, y: 0)])), nowMs: 0)
        #expect(fake.calls.isEmpty)
        #expect(ack != nil)
    }

    @Test func rateLimitDropsEventsBeyondThousandPerSecond() async throws {
        let fake = FakeEventInjector()
        let service = makeService(fake)
        for _ in 0..<30 { _ = await service.handle(try packet(Array(repeating: .move(x: 0.1, y: 0.1), count: 42)), nowMs: 0) }
        #expect(fake.calls.count == 1000)
    }

    @Test func ignoresWrongStreamAndMalformedPackets() async throws {
        let fake = FakeEventInjector()
        let service = makeService(fake)
        #expect(await service.handle(try .input(streamId: 9, events: [.move(x: 0, y: 0)]), nowMs: 0) == nil)
        let bad = MediaPacket(header: MediaHeader(type: .input, streamId: 1, frameNo: 0), payload: [1, 2, 3])
        #expect(await service.handle(bad, nowMs: 0) == nil)
        #expect(await service.malformedPacketCount == 1)
        #expect(fake.calls.isEmpty)
    }

    @Test func shutdownReleasesHeldInput() async throws {
        let fake = FakeEventInjector()
        let service = makeService(fake)
        _ = await service.handle(try packet(reliable([.button(down: true, x: 0.5, y: 0.5), .key(usage: 0xE3, down: true)])), nowMs: 0)
        await service.shutdown()
        #expect(fake.calls.suffix(2) == [.button(.left, down: false, CGPoint(x: -500, y: 250), clicks: 1), .key(55, down: false, flags: [])])
    }
}

@Suite struct TextInjectorTests {
    @Test func chunksStayWithinTwentyUtf16UnitsAndKeepCharacters() {
        let text = "Tiếng Việt có dấu, gõ nhanh hơn rất nhiều 👨‍👩‍👧 xong"
        let chunks = TextInjector.chunks(text)
        #expect(chunks.allSatisfy { $0.count <= TextInjector.chunkLimit })
        #expect(String(decoding: chunks.flatMap { $0 }, as: UTF16.self) == text)
    }

    @Test func emptyTextHasNoChunks() { #expect(TextInjector.chunks("").isEmpty) }
}
