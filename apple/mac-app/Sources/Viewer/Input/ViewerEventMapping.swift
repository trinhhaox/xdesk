import AppKit
import XdeskInput
import XdeskWire

/// Phần thuần của việc đổi NSEvent sang `InputEvent` (không đụng view) để kiểm thử được.
enum ViewerEventMapping {
    /// Một nấc chuột cuộn thường (không chính xác) quy ra bao nhiêu điểm.
    static let wheelLinePoints: Float = 10

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> InputModifiers {
        var mods: InputModifiers = []
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.capsLock) { mods.insert(.capsLock) }
        if flags.contains(.function) { mods.insert(.function) }
        return mods
    }

    /// `flagsChanged` không nói phím nào đổi: suy ra từ keyCode. Caps Lock chỉ báo trạng thái bật/tắt nên gửi cả nhấn lẫn nhả.
    static func modifierKeyEvents(macKeyCode: UInt16, flags: NSEvent.ModifierFlags) -> [InputEvent] {
        guard let usage = HidKeyMap.hidUsage(forMacKeyCode: macKeyCode), let flag = modifierFlag(macKeyCode: macKeyCode) else { return [] }
        let mods = modifiers(flags)
        if flag == .capsLock { return [.key(usage: usage, down: true, mods: mods), .key(usage: usage, down: false, mods: mods)] }
        return [.key(usage: usage, down: flags.contains(flag), mods: mods)]
    }

    static func scrollEvent(deltaX: CGFloat, deltaY: CGFloat, precise: Bool, mods: InputModifiers) -> InputEvent? {
        let factor = precise ? 1 : wheelLinePoints
        let dx = Float(deltaX) * factor, dy = Float(deltaY) * factor
        guard dx != 0 || dy != 0 else { return nil }
        // NSEvent: deltaY > 0 = nội dung đi xuống (đã gồm cuộn tự nhiên) — khớp ngữ nghĩa `InputEvent.scroll`.
        return .scroll(dx: dx, dy: dy, mods: mods)
    }

    /// ⌘Q/⌘W/⌘M/⌘H luôn ở lại viewer để thoát/đóng/thu cửa sổ được.
    static func staysLocal(macKeyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.command) && [12, 13, 46, 4].contains(macKeyCode)
    }

    private static func modifierFlag(macKeyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch macKeyCode {
        case 56, 60: .shift
        case 59, 62: .control
        case 58, 61: .option
        case 55, 54: .command
        case 57: .capsLock
        default: nil
        }
    }
}
