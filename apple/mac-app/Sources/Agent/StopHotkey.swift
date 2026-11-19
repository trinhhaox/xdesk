import Carbon.HIToolbox
import Foundation
import os

/// Phím tắt toàn cục dừng agent: ⌃⌥⌘ + `.` (dấu chấm, như ⌘. = huỷ). Dùng Carbon `RegisterEventHotKey` nên không cần quyền nào.
@MainActor
final class StopHotkey {
    static let keyCode = UInt32(kVK_ANSI_Period)
    static let modifiers = UInt32(controlKey | optionKey | cmdKey)
    static let label = "⌃⌥⌘."
    private static let log = Logger(subsystem: "vn.xox.xdesk", category: "agent-hotkey")

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (@MainActor () -> Void)?

    @discardableResult
    func register(_ action: @escaping @MainActor () -> Void) -> Bool {
        guard hotKeyRef == nil else { return true }
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, refcon in
            guard let refcon else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<StopHotkey>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { hotkey.action?() } }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x5844_4B53), id: 1)   // "XDKS"
        guard status == noErr, RegisterEventHotKey(Self.keyCode, Self.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else {
            Self.log.error("không đăng ký được phím tắt dừng")
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        action = nil
    }
}
