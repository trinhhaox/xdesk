import AppKit
import ApplicationServices
import XdeskAgent

struct AppIdentity: Sendable {
    let pid: pid_t
    let bundleId: String
    let name: String
}

/// Tìm app đích của một thao tác: cửa sổ nằm dưới con trỏ (chuột/cuộn) hoặc cửa sổ đang focus (phím), và kiểm cửa sổ đó thuộc màn hình agent.
enum AgentTargeting {
    static func identity(pid: pid_t) -> AppIdentity? {
        guard let app = NSRunningApplication(processIdentifier: pid), let bundleId = app.bundleIdentifier else { return nil }
        return AppIdentity(pid: pid, bundleId: bundleId, name: app.localizedName ?? bundleId)
    }

    /// App sở hữu cửa sổ trên cùng tại điểm toàn cục (bỏ qua cửa sổ của chính Xdesk như banner). nil = nền desktop.
    static func appUnder(point: CGPoint) -> AppIdentity? {
        let own = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in list {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict), bounds.contains(point),
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0.01 else { continue }
            return identity(pid: pid)
        }
        return nil
    }

    /// App đang focus và khung cửa sổ focus của nó (toạ độ toàn cục).
    static func focused() -> (app: AppIdentity, windowFrame: CGRect?)? {
        guard let running = NSWorkspace.shared.frontmostApplication, let app = identity(pid: running.processIdentifier) else { return nil }
        let element = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.3)
        guard let window = AxAttributes.element(element, kAXFocusedWindowAttribute) else { return (app, nil) }
        return (app, AxAttributes.frame(window))
    }

    /// Phần tử đang nhận chữ gõ có phải ô mật khẩu không (role hoặc subrole AXSecureTextField).
    static func focusedElementIsSecure() -> Bool {
        guard let running = NSWorkspace.shared.frontmostApplication else { return false }
        let app = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let element = AxAttributes.element(app, kAXFocusedUIElementAttribute) else { return false }
        return AxAttributes.string(element, kAXRoleAttribute) == "AXSecureTextField"
            || AxAttributes.string(element, kAXSubroleAttribute) == "AXSecureTextField"
    }
}

/// Đọc thuộc tính AX có kiểu, không dùng ép kiểu nguy hiểm ngoài các `CFGetTypeID` đã kiểm.
enum AxAttributes {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var out: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &out) == .success ? out : nil
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? { value(element, attribute) as? String }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let list = value(element, attribute) as? [AnyObject] else { return [] }
        return list.compactMap { $0 as CFTypeRef? }.filter { CFGetTypeID($0) == AXUIElementGetTypeID() }.map { unsafeBitCast($0, to: AXUIElement.self) }
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = point(element, kAXPositionAttribute), let size = size(element) else { return nil }
        return CGRect(origin: position, size: size)
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cgPoint, &point) ? point : nil
    }

    static func size(_ element: AXUIElement) -> CGSize? {
        guard let raw = value(element, kAXSizeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cgSize, &size) ? size : nil
    }

    @discardableResult
    static func setPosition(_ element: AXUIElement, _ point: CGPoint) -> Bool {
        var mutable = point
        guard let value = AXValueCreate(.cgPoint, &mutable) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    @discardableResult
    static func setSize(_ element: AXUIElement, _ size: CGSize) -> Bool {
        var mutable = size
        guard let value = AXValueCreate(.cgSize, &mutable) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
    }
}
