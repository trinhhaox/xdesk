import AppKit
import ApplicationServices

/// Tìm cửa sổ app dưới một điểm màn hình (toạ độ CG/AX) cho tính năng "Chỉnh cửa sổ".
enum AXWindowHitTest {
    /// Thành phần hệ thống không bao giờ là đích chỉnh cửa sổ (Dock, menu bar, trung tâm điều khiển, màn hình đăng nhập...).
    static let excludedBundleIds: Set<String> = [
        "com.apple.dock", "com.apple.systemuiserver", "com.apple.controlcenter", "com.apple.notificationcenterui",
        "com.apple.loginwindow", "com.apple.WindowManager",
    ]
    private static let messagingTimeout: Float = 0.5
    private static let maxAncestorDepth = 12

    struct Hit {
        let window: AXWindow
        let appName: String
    }

    /// Cửa sổ trên cùng tại `point`; `nil` khi là desktop, Dock, menu bar, cửa sổ của Xdesk, hoặc không truy cập được.
    @MainActor
    static func window(at point: CGPoint) -> Hit? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success, var element = hit else { return nil }
        for _ in 0..<maxAncestorDepth {
            let candidate = AXWindow(element: element)
            if candidate.string(kAXRoleAttribute) == kAXWindowRole {
                return accept(candidate)
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
                  let next = parent, CFGetTypeID(next) == AXUIElementGetTypeID() else { return nil }
            element = unsafeBitCast(next, to: AXUIElement.self)
        }
        return nil
    }

    @MainActor
    private static func accept(_ window: AXWindow) -> Hit? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window.element, &pid) == .success, pid != getpid(),
              let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy != .prohibited,
              !excludedBundleIds.contains(app.bundleIdentifier ?? ""), !window.isMinimized else { return nil }
        AXUIElementSetMessagingTimeout(window.element, messagingTimeout)
        return Hit(window: window, appName: app.localizedName ?? "")
    }
}
