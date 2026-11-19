import XdeskWire

/// Phím bổ trợ dính của thanh phím ảo: chạm một lần = áp cho phím kế tiếp rồi tự nhả,
/// chạm hai lần liên tiếp (trong `doubleTapMs`) = khoá cho tới khi chạm lần nữa.
public struct StickyModifiers: Sendable, Equatable {
    public enum State: Sendable, Equatable { case off, armed, locked }

    public static let doubleTapMs: Int64 = 400
    public static let all: [InputModifiers] = [.control, .option, .command, .shift]

    private var states: [UInt16: State] = [:]
    private struct Tap: Sendable, Equatable { var bit: UInt16, ms: Int64 }
    private var lastTap: Tap?

    public init() {}

    public func state(of modifier: InputModifiers) -> State { states[modifier.rawValue] ?? .off }

    /// Các bổ trợ đang có hiệu lực (armed hoặc locked).
    public var active: InputModifiers {
        InputModifiers(rawValue: states.reduce(0) { $1.value == .off ? $0 : $0 | $1.key })
    }

    public mutating func tap(_ modifier: InputModifiers, nowMs: Int64) {
        let bit = modifier.rawValue
        switch state(of: modifier) {
        case .off:
            states[bit] = .armed
        case .armed:
            let isDouble = lastTap.map { $0.bit == bit && nowMs - $0.ms <= Self.doubleTapMs } ?? false
            states[bit] = isDouble ? .locked : .off
        case .locked:
            states[bit] = .off
        }
        lastTap = Tap(bit: bit, ms: nowMs)
    }

    /// Lấy bổ trợ cho một phím rồi nhả loại armed (loại locked giữ nguyên).
    public mutating func consume() -> InputModifiers {
        let current = active
        for (bit, state) in states where state == .armed { states[bit] = .off }
        return current
    }

    public mutating func reset() {
        states.removeAll()
        lastTap = nil
    }
}
