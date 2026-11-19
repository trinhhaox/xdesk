import CoreGraphics
import Foundation
import os

/// Phát hiện người thật chạm vào màn hình agent bằng CGEventTap `listenOnly` (không chặn, không sửa sự kiện).
///
/// Phân biệt thật/giả: sự kiện phần cứng đi vào qua HID có `eventSourceUnixProcessID == 0`; mọi sự kiện do một tiến trình
/// tiêm (kể cả của chính Xdesk) mang pid của tiến trình đó, và sự kiện của agent còn có `eventSourceUserData == marker`.
/// Chỉ "thật" khi pid == 0 và không có marker. Chuột: tính khi con trỏ nằm trong màn hình agent (trừ vùng banner để nút
/// Tiếp tục/Dừng bấm được). Phím: tính khi con trỏ đang ở trên màn hình agent (nơi agent để lại focus).
/// Cần quyền "Giám sát đầu vào"; thiếu quyền thì `start()` trả false và UI báo rõ.
final class HumanInputMonitor: @unchecked Sendable {
    private static let log = Logger(subsystem: "vn.xox.xdesk", category: "agent-input-monitor")
    private let displayBounds: @Sendable () -> CGRect?
    private let ignoredRects: @Sendable () -> [CGRect]
    private let onHumanInput: @Sendable () -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    init(displayBounds: @escaping @Sendable () -> CGRect?, ignoredRects: @escaping @Sendable () -> [CGRect], onHumanInput: @escaping @Sendable () -> Void) {
        self.displayBounds = displayBounds
        self.ignoredRects = ignoredRects
        self.onHumanInput = onHumanInput
    }

    var isRunning: Bool { tap != nil }

    /// Gọi trên main thread (gắn vào run loop chính).
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .leftMouseDragged, .rightMouseDown, .rightMouseDragged, .otherMouseDown, .scrollWheel, .keyDown,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                Unmanaged<HumanInputMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            Self.log.error("không tạo được event tap (thiếu quyền Giám sát đầu vào?)")
            return false
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        tap = created
        source = runLoopSource
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard Self.isHuman(event), let bounds = displayBounds() else { return }
        // Với phím, vị trí sự kiện không có nghĩa: dùng vị trí con trỏ hiện tại.
        let location = type == .keyDown ? (CGEvent(source: nil)?.location ?? .zero) : event.location
        guard bounds.contains(location), !ignoredRects().contains(where: { $0.contains(location) }) else { return }
        onHumanInput()
    }

    static func isHuman(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUnixProcessID) == 0 && event.getIntegerValueField(.eventSourceUserData) != AgentEventPoster.marker
    }
}
