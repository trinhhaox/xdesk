import AppKit

/// Ô "Chụp phím hệ thống" trên thanh tiêu đề cửa sổ viewer; mặc định tắt. Bật cần quyền Trợ năng.
@MainActor
final class ShortcutCaptureToggle: NSObject {
    private let window: NSWindow
    private let tap: SystemShortcutTap
    private let checkbox: NSButton

    init(window: NSWindow, capture: ViewerEventCapture) {
        self.window = window
        tap = SystemShortcutTap(
            isTargetActive: { [weak window] in NSApp.isActive && window?.isKeyWindow == true },
            forward: { [weak capture] code, down, flags in capture?.forwardSystemKey(macKeyCode: code, down: down, flags: flags) }
        )
        checkbox = NSButton(checkboxWithTitle: String(localized: "Chụp phím hệ thống (⌘-Tab, ⌘-Space)"), target: nil, action: nil)
        super.init()
        checkbox.target = self
        checkbox.action = #selector(toggled)
        checkbox.toolTip = String(localized: "Gửi ⌘-Tab và ⌘-Space sang máy được điều khiển thay vì xử lý trên Mac này. Cần quyền Trợ năng.")
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        accessory.view = checkbox
        window.addTitlebarAccessoryViewController(accessory)
    }

    func stop() { tap.stop() }

    @objc private func toggled() {
        guard checkbox.state == .on else { return tap.stop() }
        guard AccessibilityPermission.isGranted, tap.start() else {
            checkbox.state = .off
            showPermissionAlert()
            return
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = AccessibilityPermission.menuTitle
        alert.informativeText = AccessibilityPermission.guidance
        alert.addButton(withTitle: String(localized: "Mở Cài đặt"))
        alert.addButton(withTitle: String(localized: "Để sau"))
        if alert.runModal() == .alertFirstButtonReturn { AccessibilityPermission.openSettings() }
    }
}
