import ApplicationServices
import Foundation

/// Đưa cửa sổ của một app lên màn hình agent bằng AX (đặt vị trí/kích thước).
enum WindowMover {
    static func windows(of pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        return AxAttributes.elements(app, kAXWindowsAttribute)
    }

    /// Chờ tới ~6 s cho cửa sổ mới xuất hiện (không nằm trong `excluding`) rồi dời lên màn hình agent. Trả về số cửa sổ đã dời.
    static func moveNewWindows(pid: pid_t, excluding: [AXUIElement], to origin: CGPoint, within size: CGSize) async -> Int {
        var moved: [AXUIElement] = []
        for _ in 0..<30 {
            for window in windows(of: pid) where !excluding.contains(where: { CFEqual($0, window) }) && !moved.contains(where: { CFEqual($0, window) }) {
                place(window, origin: CGPoint(x: origin.x + 40 + Double(moved.count) * 24, y: origin.y + 70 + Double(moved.count) * 24), within: size)
                moved.append(window)
            }
            if !moved.isEmpty { try? await Task.sleep(for: .milliseconds(400)); break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        if let first = moved.first { AXUIElementPerformAction(first, kAXRaiseAction as CFString) }
        return moved.count
    }

    private static func place(_ window: AXUIElement, origin: CGPoint, within size: CGSize) {
        if let current = AxAttributes.size(window), current.width > size.width - 80 || current.height > size.height - 120 {
            AxAttributes.setSize(window, CGSize(width: min(current.width, size.width - 80), height: min(current.height, size.height - 120)))
        }
        AxAttributes.setPosition(window, origin)
    }
}
