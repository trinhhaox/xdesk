import XdeskWire

public enum ModifierKeyState: Sendable, Equatable { case off, armed, locked }

/// Máy trạng thái bàn phím Mac ảo: nhận chạm xuống/lên theo từng ngón (`touchId`), trả về các `InputEvent`
/// HID cần gửi. Phím thường gửi key down lúc chạm xuống, key up lúc nhả, giữ thì lặp bằng `KeyRepeater`.
/// Phím bổ trợ: chạm nhanh = dính một lần (tự nhả sau phím kế tiếp), chạm đúp = khoá, giữ + phím khác = tổ hợp.
public struct MacKeyboardController: Sendable {
    public static let doubleTapMs: Int64 = 400
    /// Giữ lâu hơn mức này (không chạm đúp) thì nhả bổ trợ khi nhấc tay, như phím thật.
    public static let holdMs: Int64 = 350

    private enum TouchKind { case key, modifier, capsLock }
    private struct Touch {
        var usage: UInt16
        var kind: TouchKind
        var downMs: Int64
        var chord = false
        /// Chạm vào bổ trợ đang dính: nhấc nhanh mà không có phím khác = huỷ.
        var wasArmed = false
        var consume: [UInt16] = []
        var mods: InputModifiers = []
    }
    private struct Tap { var usage: UInt16; var ms: Int64 }

    private var touches: [Int: Touch] = [:]
    private var states: [UInt16: ModifierKeyState] = [:]
    private var bits: [UInt16: InputModifiers] = [:]
    /// Bổ trợ đã gửi key down mà chưa gửi key up (kể cả loại đã tiêu thụ đang chờ phím thường nhả).
    private var sentDown: Set<UInt16> = []
    private var lastTap: Tap?
    private var repeater = KeyRepeater()
    public private(set) var capsLockOn = false

    public init() {}

    public var isRepeating: Bool { repeater.isRepeating }
    public var pressedUsages: Set<UInt16> { Set(touches.values.map(\.usage)) }
    public func state(ofModifierUsage usage: UInt16) -> ModifierKeyState { states[usage] ?? .off }

    /// Bổ trợ đang có hiệu lực (dính, khoá hoặc đang giữ).
    public var activeMods: InputModifiers {
        states.reduce(into: InputModifiers()) { acc, entry in
            if entry.value != .off, let bit = bits[entry.key] { acc.insert(bit) }
        }
    }

    public mutating func press(touchId: Int, key: MacKey, nowMs: Int64) -> [InputEvent] {
        guard touches[touchId] == nil else { return [] }
        if let modifier = key.modifier { return pressModifier(touchId, key.usage, modifier, nowMs) }
        if key.kind == .capsLock { return pressCapsLock(touchId, key.usage, nowMs) }
        return pressKey(touchId, key.usage, nowMs)
    }

    public mutating func release(touchId: Int, nowMs: Int64) -> [InputEvent] {
        guard let touch = touches.removeValue(forKey: touchId) else { return [] }
        switch touch.kind {
        case .capsLock:
            return []
        case .key:
            repeater.keyUp(usage: touch.usage)
            var events: [InputEvent] = [.key(usage: touch.usage, down: false, mods: touch.mods)]
            // Bổ trợ đã được dính lại trong lúc phím còn giữ thì giữ nguyên, không nhả.
            for usage in touch.consume where state(ofModifierUsage: usage) == .off { events += modifierUp(usage) }
            return events
        case .modifier:
            let isMomentary = touch.chord || nowMs - touch.downMs > Self.holdMs || touch.wasArmed
            guard states[touch.usage] == .armed, isMomentary else { return [] }
            states[touch.usage] = .off
            return modifierUp(touch.usage)
        }
    }

    /// Gọi định kỳ (~50 ms): các `key down` lặp đã đến hạn.
    public mutating func tick(nowMs: Int64) -> [InputEvent] { repeater.tick(nowMs: nowMs) }

    /// Rời chế độ / nền / mất kết nối: nhả mọi phím và bổ trợ (kể cả loại khoá) để host không bị kẹt.
    /// Caps Lock giữ nguyên (sống theo phiên, xoá bằng `clearCapsLock`).
    public mutating func releaseAll() -> [InputEvent] {
        var events: [InputEvent] = touches.values
            .filter { $0.kind == .key }
            .sorted { $0.usage < $1.usage }
            .map { .key(usage: $0.usage, down: false, mods: []) }
        events += sentDown.sorted().map { .key(usage: $0, down: false, mods: []) }
        touches.removeAll()
        states.removeAll()
        sentDown.removeAll()
        lastTap = nil
        repeater.releaseAll()
        return events
    }

    // MARK: - Private

    private mutating func pressModifier(_ id: Int, _ usage: UInt16, _ modifier: InputModifiers, _ nowMs: Int64) -> [InputEvent] {
        bits[usage] = modifier
        touches[id] = Touch(usage: usage, kind: .modifier, downMs: nowMs)
        switch state(ofModifierUsage: usage) {
        case .off:
            states[usage] = .armed
            lastTap = Tap(usage: usage, ms: nowMs)
            sentDown.insert(usage)
            return [.key(usage: usage, down: true, mods: activeMods)]
        case .armed:
            let isDouble = lastTap.map { $0.usage == usage && nowMs - $0.ms <= Self.doubleTapMs } ?? false
            lastTap = nil
            if isDouble {
                states[usage] = .locked
                return []
            }
            // Chạm lại sau cửa sổ chạm đúp: vẫn dính, tính giờ lại; quyết định lúc nhấc tay.
            touches[id]?.wasArmed = true
            lastTap = Tap(usage: usage, ms: nowMs)
            return []
        case .locked:
            states[usage] = .off
            return modifierUp(usage)
        }
    }

    /// Caps Lock chỉ sống trên điện thoại: không gửi HID, chỉ bật/tắt cờ `.capsLock` trên các phím sau.
    private mutating func pressCapsLock(_ id: Int, _ usage: UInt16, _ nowMs: Int64) -> [InputEvent] {
        capsLockOn.toggle()
        touches[id] = Touch(usage: usage, kind: .capsLock, downMs: nowMs)
        return []
    }

    /// Tắt Caps Lock (khi ngắt kết nối phiên).
    public mutating func clearCapsLock() { capsLockOn = false }

    private mutating func pressKey(_ id: Int, _ usage: UInt16, _ nowMs: Int64) -> [InputEvent] {
        var heldModifiers: Set<UInt16> = []
        for (touchId, touch) in touches where touch.kind == .modifier {
            touches[touchId]?.chord = true
            heldModifiers.insert(touch.usage)
        }
        let armed = states.filter { $0.value == .armed && !heldModifiers.contains($0.key) }.keys.sorted()
        var mods = activeMods
        if capsLockOn { mods.insert(.capsLock) }
        for usage in armed { states[usage] = .off }
        var touch = Touch(usage: usage, kind: .key, downMs: nowMs)
        touch.consume = armed
        touch.mods = mods
        touches[id] = touch
        repeater.keyDown(usage: usage, mods: mods, nowMs: nowMs)
        return [.key(usage: usage, down: true, mods: mods)]
    }

    private mutating func modifierUp(_ usage: UInt16) -> [InputEvent] {
        guard sentDown.remove(usage) != nil else { return [] }
        return [.key(usage: usage, down: false, mods: activeMods)]
    }
}
