import AppKit
import SwiftUI
import XdeskMedia

/// Cửa sổ hiển thị luồng video của một `ViewerSession` (AVSampleBufferDisplayLayer). Đóng cửa sổ = ngắt kết nối.
@MainActor
final class ViewerWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let session: ViewerSession
    private let onClose: @MainActor () -> Void

    init(session: ViewerSession, title: String, fullScreen: Bool, latencyOverlay: Bool, onClose: @escaping @MainActor () -> Void) {
        self.session = session
        self.onClose = onClose
        let content = VideoContainerView(renderer: session.renderer)
        if latencyOverlay { content.addOverlay(LatencyOverlayView(session: session)) }
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false
        )
        super.init()
        window.title = title
        window.contentView = content
        window.contentAspectRatio = NSSize(width: 16, height: 10)
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if fullScreen { window.toggleFullScreen(nil) }
    }

    func close() {
        window.delegate = nil
        window.close()
    }

    func windowWillClose(_ notification: Notification) { onClose() }
}

/// View gắn `AVSampleBufferDisplayLayer` làm layer nền, co theo khung.
final class VideoContainerView: NSView {
    private let videoLayer: CALayer

    @MainActor
    init(renderer: VideoLayerRenderer) {
        videoLayer = renderer.layer
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(videoLayer)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        videoLayer.frame = bounds
    }

    func addOverlay(_ view: NSView) {
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 40)
        view.autoresizingMask = [.maxXMargin, .maxYMargin]
        addSubview(view)
    }
}
