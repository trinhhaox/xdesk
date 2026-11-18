public enum InputKind: UInt8, Sendable, CaseIterable {
    case move = 0, down = 1, up = 2, scroll = 3, key = 4, textRef = 5, touch = 6
}

/// Sự kiện input cố định 28 byte:
/// `u8 kind | u8 button | u16 mods | u32 seq | f32 x | f32 y | f32 dx | f32 dy | u16 keyUsage | u16 pad`.
/// Toạ độ `x`,`y` chuẩn hoá 0…1 theo khung video với move/down/up/touch.
public struct InputEvent: Sendable, Equatable {
    public static let size = 28
    public static let maxBatch = MediaPacket.maxPayload / size

    public var kind: InputKind
    public var button: UInt8
    public var mods: UInt16
    public var seq: UInt32
    public var x: Float
    public var y: Float
    public var dx: Float
    public var dy: Float
    public var keyUsage: UInt16

    public init(
        kind: InputKind, button: UInt8 = 0, mods: UInt16 = 0, seq: UInt32, x: Float = 0, y: Float = 0,
        dx: Float = 0, dy: Float = 0, keyUsage: UInt16 = 0
    ) {
        self.kind = kind; self.button = button; self.mods = mods; self.seq = seq
        self.x = x; self.y = y; self.dx = dx; self.dy = dy; self.keyUsage = keyUsage
    }

    private var isPointerKind: Bool { [.move, .down, .up, .touch].contains(kind) }

    func validate() throws {
        guard x.isFinite, y.isFinite, dx.isFinite, dy.isFinite else { throw WireError.invalidInput("non-finite float") }
        if isPointerKind, !(0...1).contains(x) || !(0...1).contains(y) { throw WireError.invalidInput("coordinate out of 0...1") }
    }

    func write(to w: inout ByteWriter) throws {
        try validate()
        w.u8(kind.rawValue); w.u8(button); w.u16(mods); w.u32(seq)
        w.f32(x); w.f32(y); w.f32(dx); w.f32(dy)
        w.u16(keyUsage); w.u16(0)
    }

    static func read(from r: inout ByteReader) throws -> InputEvent {
        let rawKind = try r.u8()
        guard let kind = InputKind(rawValue: rawKind) else { throw WireError.invalidInput("unknown kind \(rawKind)") }
        let button = try r.u8()
        let mods = try r.u16()
        let seq = try r.u32()
        let x = try r.f32(), y = try r.f32(), dx = try r.f32(), dy = try r.f32()
        let keyUsage = try r.u16()
        _ = try r.u16() // pad: bỏ qua khi đọc để chừa chỗ mở rộng
        let event = InputEvent(kind: kind, button: button, mods: mods, seq: seq, x: x, y: y, dx: dx, dy: dy, keyUsage: keyUsage)
        try event.validate()
        return event
    }

    /// Payload của gói `input`: 1…`maxBatch` sự kiện nối nhau.
    public static func encodeBatch(_ events: [InputEvent]) throws -> [UInt8] {
        guard (1...maxBatch).contains(events.count) else { throw WireError.invalidInput("batch size \(events.count)") }
        var w = ByteWriter(capacity: events.count * size)
        for e in events { try e.write(to: &w) }
        return w.bytes
    }

    public static func decodeBatch(_ payload: [UInt8]) throws -> [InputEvent] {
        guard !payload.isEmpty, payload.count % size == 0, payload.count / size <= maxBatch else {
            throw WireError.invalidInput("payload length \(payload.count)")
        }
        var r = ByteReader(payload)
        var events: [InputEvent] = []
        while r.remaining > 0 { events.append(try read(from: &r)) }
        return events
    }
}

/// Payload của gói `input-ack`: `u32 seq` — seq lớn nhất mà phía nhận đã nhận liên tục.
public struct InputAck: Sendable, Equatable {
    public static let size = 4
    public var seq: UInt32

    public init(seq: UInt32) { self.seq = seq }

    public func encode() -> [UInt8] {
        var w = ByteWriter(capacity: Self.size)
        w.u32(seq)
        return w.bytes
    }

    public static func decode(_ payload: [UInt8]) throws -> InputAck {
        guard payload.count == size else { throw WireError.invalidInput("ack length \(payload.count)") }
        var r = ByteReader(payload)
        return InputAck(seq: try r.u32())
    }
}
