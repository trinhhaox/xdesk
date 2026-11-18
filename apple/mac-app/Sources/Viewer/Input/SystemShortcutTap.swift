import AppKit
import CoreGraphics

/// Chặn ⌘-Tab / ⌘-Space khi cửa sổ viewer đang là cửa sổ chính để chuyển sang host thay vì Mac viewer xử lý.
/// Cần quyền Trợ năng; `start()` trả `false` nếu hệ thống từ chối tạo tap.
@MainActor
final class SystemShortcutTap {
    private static let tab: Int64 = 48
    private static let space: Int64 = 49

    private let isTargetActive: @MainActor () -> Bool
    private let forward: @MainActor (_ macKeyCode: UInt16, _ down: Bool, _ flags: NSEvent.ModifierFlags) -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    init(
        isTargetActive: @escaping @MainActor () -> Bool,
        forward: @escaping @MainActor (_ macKeyCode: UInt16, _ down: Bool, _ flags: NSEvent.ModifierFlags) -> Void
    ) {
        self.isTargetActive = isTargetActive
        self.forward = forward
    }

    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<SystemShortcutTap>.fromOpaque(userInfo).takeUnretainedValue()
            let swallowed = MainActor.assumeIsolated { owner.handle(type: type, event: event) }
            return swallowed ? nil : Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = runLoopSource
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type == .keyDown || type == .keyUp, event.flags.contains(.maskCommand), isTargetActive() else { return false }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        guard code == Self.tab || code == Self.space else { return false }
        forward(UInt16(code), type == .keyDown, NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)))
        return true
    }
}
