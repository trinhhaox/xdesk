import CoreGraphics
import Foundation
import XdeskAgent
import XdeskInput

/// Tiêm input của agent. Mọi sự kiện mang `marker` trong `eventSourceUserData` (và pid của Xdesk) để `HumanInputMonitor`
/// phân biệt với thao tác thật của người: sự kiện phần cứng có `eventSourceUnixProcessID == 0` và không có marker.
/// Dùng nguồn `.privateState` nên phím bổ trợ người đang giữ không lẫn vào sự kiện của agent.
struct AgentEventPoster: Sendable {
    static let marker: Int64 = 0x5844_4B41   // "XDKA"
    private static let step = Duration.milliseconds(15)

    private var source: CGEventSource? {
        let source = CGEventSource(stateID: .privateState)
        source?.userData = Self.marker
        return source
    }

    func move(to point: CGPoint) {
        post(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left))
    }

    func click(at point: CGPoint, button: CGMouseButton = .left, count: Int = 1) async throws {
        move(to: point)
        try await Task.sleep(for: Self.step)
        let (down, up): (CGEventType, CGEventType) = button == .right ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
        for index in 1...count {
            for type in [down, up] {
                let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)
                event?.setIntegerValueField(.mouseEventClickState, value: Int64(index))
                post(event)
                try await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    func drag(from start: CGPoint, to end: CGPoint) async throws {
        move(to: start)
        try await Task.sleep(for: Self.step)
        post(CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left))
        let steps = 12
        for index in 1...steps {
            let t = CGFloat(index) / CGFloat(steps)
            let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            post(CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left))
            try await Task.sleep(for: Self.step)
        }
        post(CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left))
    }

    func scroll(dx: Int32, dy: Int32) {
        post(CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: -dy, wheel2: -dx, wheel3: 0))
    }

    func press(_ chord: KeyChord) async throws {
        let flags = Self.flags(chord.modifiers)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(chord.keyCode), keyDown: down)
            event?.flags = flags
            post(event)
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Gõ Unicode theo cụm ≤ 20 đơn vị UTF-16 (giữ nguyên dấu tiếng Việt, không phụ thuộc bàn phím đang bật).
    func type(_ text: String) async throws {
        for var chunk in TextInjector.chunks(text) {
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                post(event)
            }
            try await Task.sleep(for: .milliseconds(8))
        }
    }

    private func post(_ event: CGEvent?) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.post(tap: .cghidEventTap)
    }

    private static func flags(_ modifiers: KeyChord.Modifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }
}
