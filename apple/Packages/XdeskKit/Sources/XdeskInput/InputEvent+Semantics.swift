import XdeskWire

/// Bitmask `mods` của `InputEvent` (bit khớp spec media-packets.md).
public struct InputModifiers: OptionSet, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let shift = InputModifiers(rawValue: 1)
    public static let control = InputModifiers(rawValue: 2)
    public static let option = InputModifiers(rawValue: 4)
    public static let command = InputModifiers(rawValue: 8)
    public static let capsLock = InputModifiers(rawValue: 16)
    public static let function = InputModifiers(rawValue: 32)
}

/// Giá trị `button` của down/up.
public enum InputButton {
    public static let left: UInt8 = 0
    public static let right: UInt8 = 1
    public static let other: UInt8 = 2
}

/// Hàm dựng sự kiện theo đúng ngữ nghĩa trên dây; `seq` = 0 (do `InputSequencer` cấp cho sự kiện cần tin cậy).
extension InputEvent {
    public static func move(x: Float, y: Float, mods: InputModifiers = []) -> InputEvent {
        InputEvent(kind: .move, mods: mods.rawValue, seq: 0, x: x, y: y)
    }

    /// `clickCount` (1, 2, 3…) đi trong `dx`; 0 được hiểu là 1.
    public static func button(
        down: Bool, button: UInt8 = InputButton.left, x: Float, y: Float, clickCount: Int = 1, mods: InputModifiers = []
    ) -> InputEvent {
        InputEvent(kind: down ? .down : .up, button: button, mods: mods.rawValue, seq: 0, x: x, y: y, dx: Float(clickCount))
    }

    /// Cuộn theo pixel điểm của host; `dy` > 0 = nội dung đi xuống (ngón kéo xuống).
    public static func scroll(dx: Float, dy: Float, mods: InputModifiers = []) -> InputEvent {
        InputEvent(kind: .scroll, mods: mods.rawValue, seq: 0, dx: dx, dy: dy)
    }

    /// Phím theo HID usage; `button` = 1 nhấn, 0 nhả.
    public static func key(usage: UInt16, down: Bool, mods: InputModifiers = []) -> InputEvent {
        InputEvent(kind: .key, button: down ? 1 : 0, mods: mods.rawValue, seq: 0, keyUsage: usage)
    }

    /// Cuộn (0, 0): host không làm gì nhưng coi là còn sống, tránh watchdog nhả nút đang giữ.
    public static let heartbeat = InputEvent.scroll(dx: 0, dy: 0)

    /// Down/up/key cần giao chắc chắn (seq + input-ack); move/scroll bỏ mất cũng được.
    public var isReliable: Bool { kind == .down || kind == .up || kind == .key }

    /// Ép toạ độ vào 0…1 (sự kiện con trỏ) và loại sự kiện có số không hữu hạn; bộ mã hoá từ chối cả lô nếu có một sự kiện sai.
    public func sanitized() -> InputEvent? {
        guard x.isFinite, y.isFinite, dx.isFinite, dy.isFinite else { return nil }
        var copy = self
        if [.move, .down, .up, .touch].contains(kind) {
            copy.x = min(1, max(0, x))
            copy.y = min(1, max(0, y))
        }
        return copy
    }
}
