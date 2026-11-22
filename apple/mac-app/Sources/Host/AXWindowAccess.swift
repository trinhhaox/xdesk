import ApplicationServices
import CoreGraphics

/// Đọc/ghi cửa sổ qua Accessibility API (cần quyền Trợ năng, Xdesk đã xin để gửi input).
struct AXWindow {
    let element: AXUIElement

    var key: UInt { UInt(CFHash(element)) }

    /// Cửa sổ thường (không phải panel/dialog/sheet), đang hiện, không toàn màn hình, đổi được kích thước.
    var isFittable: Bool {
        string(kAXRoleAttribute) == kAXWindowRole && string(kAXSubroleAttribute) == kAXStandardWindowSubrole
            && bool("AXFullScreen") != true && bool(kAXMinimizedAttribute) != true && isSettable(kAXSizeAttribute) && isSettable(kAXPositionAttribute)
    }

    var frame: CGRect? {
        guard let origin = point(kAXPositionAttribute), let size = size(kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    var currentSize: CGSize? { size(kAXSizeAttribute) }

    var title: String? { string(kAXTitleAttribute) }

    /// Cửa sổ có thể đổi kích thước (thuộc tính `AXSize` ghi được).
    var isResizable: Bool { isSettable(kAXSizeAttribute) }

    var isMinimized: Bool { bool(kAXMinimizedAttribute) == true }

    /// Đặt vị trí rồi kích thước rồi vị trí lại (đổi kích thước có thể bị macOS dịch cửa sổ).
    @discardableResult
    func set(frame: CGRect) -> Bool {
        let first = set(kAXPositionAttribute, point: frame.origin)
        let resized = set(kAXSizeAttribute, size: frame.size)
        let last = set(kAXPositionAttribute, point: frame.origin)
        return first && resized && last
    }

    @discardableResult
    func move(to origin: CGPoint) -> Bool { set(kAXPositionAttribute, point: origin) }

    static func windows(ofPid pid: pid_t) -> [AXWindow] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list.map(AXWindow.init)
    }

    func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    func string(_ name: String) -> String? { attribute(name) as? String }
    private func bool(_ name: String) -> Bool? { attribute(name) as? Bool }

    func isSettable(_ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }

    private func point(_ name: String) -> CGPoint? {
        guard let raw = attribute(name), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var result = CGPoint.zero
        return AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cgPoint, &result) ? result : nil
    }

    private func size(_ name: String) -> CGSize? {
        guard let raw = attribute(name), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var result = CGSize.zero
        return AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cgSize, &result) ? result : nil
    }

    private func set(_ name: String, point: CGPoint) -> Bool {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(element, name as CFString, value) == .success
    }

    private func set(_ name: String, size: CGSize) -> Bool {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(element, name as CFString, value) == .success
    }
}
