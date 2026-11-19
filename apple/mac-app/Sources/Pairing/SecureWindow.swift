import AppKit
import SwiftUI

/// Danh sách CGWindowID của các cửa sổ nhạy cảm (mã QR, mã so khớp) để `CaptureService` loại khỏi luồng stream.
final class SecureWindowRegistry: @unchecked Sendable {
    static let shared = SecureWindowRegistry()
    private let lock = NSLock()
    private var ids: Set<CGWindowID> = []

    var windowIDs: Set<CGWindowID> { lock.withLock { ids } }
    func insert(_ id: CGWindowID) { lock.withLock { _ = ids.insert(id) } }
    func remove(_ id: CGWindowID) { lock.withLock { _ = ids.remove(id) } }
}

/// Cửa sổ không bị chụp/ghi hình: `sharingType = .none` và đăng ký vào `SecureWindowRegistry` TRƯỚC khi hiện
/// (macOS mới không phải lúc nào cũng tôn trọng `sharingType` với ScreenCaptureKit nên cần cả bộ lọc ở capture).
@MainActor
final class SecureWindow: NSObject, NSWindowDelegate {
    fileprivate let window: NSWindow
    private let windowID: CGWindowID
    private let onClose: () -> Void
    private var closed = false

    init(title: String, floating: Bool, onClose: @escaping () -> Void, content: some View) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 500), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        self.onClose = onClose
        windowID = CGWindowID(window.windowNumber)
        super.init()
        window.title = title
        window.sharingType = .none
        window.isReleasedWhenClosed = false
        window.level = floating ? .floating : .normal
        window.contentViewController = NSHostingController(rootView: content)
        window.delegate = self
        window.center()
        SecureWindowRegistry.shared.insert(windowID)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window.close() }

    func windowWillClose(_ notification: Notification) {
        guard !closed else { return }
        closed = true
        SecureWindowRegistry.shared.remove(windowID)
        onClose()
    }
}

#if DEBUG
extension SecureWindow {
    /// Kiểm thử: vẽ nội dung cửa sổ ra PNG ngay trong tiến trình (cửa sổ `sharingType = .none` không chụp được bằng `screencapture`).
    func writeSnapshot(to path: String) -> Bool {
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    var windowFrameDescription: String { NSStringFromRect(window.frame) }
}
#endif
