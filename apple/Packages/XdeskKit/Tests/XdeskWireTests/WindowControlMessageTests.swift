import Testing
@testable import XdeskWire

@Suite struct WindowControlMessageTests {
    private func roundTrip(_ message: ControlMessage) throws -> ControlMessage {
        try ControlMessageCodec.decode(try ControlMessageCodec.encode(ControlEnvelope(id: 9, message: message))).message
    }

    @Test func capabilityBitIs14() {
        #expect(Capabilities.windowControl.rawValue == 0x4000)
    }

    @Test func roundTripsAllWindowMessages() throws {
        let all: [ControlMessage] = [
            .windowPick(WindowPick(x: 10.5, y: 20)),
            .windowSelected(WindowSelected(ok: true, windowId: 3, app: "Safari", title: "Tiêu đề", frame: WindowFrame(x: 1, y: 2, w: 300, h: 200), resizable: true)),
            .windowSelected(.failure("Không có cửa sổ ở đây")),
            .windowAdjust(.move(windowId: 3, dx: -4, dy: 8.5)),
            .windowAdjust(.resize(windowId: 3, w: 640, h: 480)),
        ] + WindowPreset.allCases.map { .windowAdjust(.preset(windowId: 3, $0)) }
        for message in all { #expect(try roundTrip(message) == message) }
    }

    @Test func rejectsInvalidValues() {
        let bad: [ControlMessage] = [
            .windowPick(WindowPick(x: .nan, y: 0)),
            .windowAdjust(WindowAdjust(windowId: 1, op: .move, dx: 1)),
            .windowAdjust(.move(windowId: 1, dx: .infinity, dy: 0)),
            .windowAdjust(.resize(windowId: 1, w: 0, h: 10)),
            .windowAdjust(WindowAdjust(windowId: 1, op: .preset)),
            .windowSelected(WindowSelected(ok: true, frame: WindowFrame(x: 0, y: 0, w: -1, h: 5))),
        ]
        for message in bad {
            #expect(throws: WireError.self) { try ControlMessageCodec.encode(ControlEnvelope(id: 1, message: message)) }
        }
    }
}
