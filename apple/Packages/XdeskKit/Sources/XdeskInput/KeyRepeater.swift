import XdeskWire

/// Lặp phím phía viewer: giữ phím không phải modifier quá `delayMs` thì phát lại `key down`
/// mỗi `intervalMs` (host không tự lặp). Chỉ phím nhấn gần nhất được lặp, như bàn phím thật.
public struct KeyRepeater: Sendable {
    public static let defaultDelayMs: Int64 = 400
    public static let defaultIntervalMs: Int64 = 33
    private static let maxBurst: Int64 = 4
    /// HID usage 0xE0…0xE7 là Ctrl/Shift/Alt/GUI trái-phải.
    private static let modifierUsages: ClosedRange<UInt16> = 0xE0...0xE7

    private let delayMs: Int64
    private let intervalMs: Int64
    private var held: (usage: UInt16, mods: InputModifiers, nextFireMs: Int64)?

    public init(delayMs: Int64 = defaultDelayMs, intervalMs: Int64 = defaultIntervalMs) {
        self.delayMs = delayMs
        self.intervalMs = max(1, intervalMs)
    }

    public var isRepeating: Bool { held != nil }

    public mutating func keyDown(usage: UInt16, mods: InputModifiers, nowMs: Int64) {
        guard !Self.modifierUsages.contains(usage) else { return }
        held = (usage, mods, nowMs + delayMs)
    }

    public mutating func keyUp(usage: UInt16) {
        if held?.usage == usage { held = nil }
    }

    public mutating func releaseAll() { held = nil }

    /// Gọi định kỳ (~50 ms); trả các `key down` lặp đã đến hạn (tối đa vài cái mỗi lần để không dồn cục).
    public mutating func tick(nowMs: Int64) -> [InputEvent] {
        guard var key = held, nowMs >= key.nextFireMs else { return [] }
        let due = min(Self.maxBurst, (nowMs - key.nextFireMs) / intervalMs + 1)
        key.nextFireMs = nowMs + intervalMs
        held = key
        return (0..<due).map { _ in .key(usage: key.usage, down: true, mods: key.mods) }
    }
}
