import CoreGraphics
import Foundation
import os
import XdeskInput

/// Tiêm bằng `CGEvent` vào `.cghidEventTap` (cần quyền Trợ năng; thiếu quyền thì hệ thống lặng lẽ bỏ sự kiện).
struct CGEventInjector: EventInjecting {
    private static let log = Logger(subsystem: "vn.xox.xdesk", category: "event-injector")

    func mouseMove(to point: CGPoint, held: MouseButton?, flags: CGEventFlags) {
        let type: CGEventType
        switch held {
        case .none: type = .mouseMoved
        case .left?: type = .leftMouseDragged
        case .right?: type = .rightMouseDragged
        case .other?: type = .otherMouseDragged
        }
        post(CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: held.map(Self.cgButton) ?? .left), flags: flags)
    }

    func mouseButton(_ button: MouseButton, down: Bool, at point: CGPoint, clickCount: Int, flags: CGEventFlags) {
        let type: CGEventType
        switch button {
        case .left: type = down ? .leftMouseDown : .leftMouseUp
        case .right: type = down ? .rightMouseDown : .rightMouseUp
        case .other: type = down ? .otherMouseDown : .otherMouseUp
        }
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: Self.cgButton(button))
        event?.setIntegerValueField(.mouseEventClickState, value: Int64(max(1, clickCount)))
        post(event, flags: flags)
    }

    func scroll(dx: Int32, dy: Int32, flags: CGEventFlags) {
        post(CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0), flags: flags)
    }

    func key(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        post(CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down), flags: flags)
    }

    private var source: CGEventSource? { CGEventSource(stateID: .combinedSessionState) }

    private func post(_ event: CGEvent?, flags: CGEventFlags) {
        guard let event else {
            Self.log.error("không tạo được CGEvent")
            return
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private static func cgButton(_ button: MouseButton) -> CGMouseButton {
        switch button {
        case .left: .left
        case .right: .right
        case .other: .center
        }
    }
}

extension InputModifiers {
    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.capsLock) { flags.insert(.maskAlphaShift) }
        if contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }
}
