import AppKit
import XdeskInput
import XdeskMedia
import XdeskViewer
import XdeskWire

/// Lớp trong suốt phủ video: bắt chuột/trackpad/bàn phím và gửi sang host, toạ độ chuẩn hoá theo khung video
/// (bỏ dải letterbox). Cuộn trackpad (kể cả quán tính) đi dưới dạng pixel.
@MainActor
final class ViewerEventCapture: NSView {
    private let session: ViewerSession
    private let renderer: VideoLayerRenderer
    private var heldButtons: Set<UInt8> = []
    private var heldKeys: Set<UInt16> = []
    private var trackingArea: NSTrackingArea?

    init(session: ViewerSession, renderer: VideoLayerRenderer) {
        self.session = session
        self.renderer = renderer
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard let window else { return }
        window.acceptsMouseMovedEvents = true
        window.makeFirstResponder(self)
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowLostFocus), name: NSWindow.didResignKeyNotification, object: window
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    /// Mất focus: nhả hết nút/phím đang giữ để host không bị kẹt.
    @objc func windowLostFocus() {
        let ups = heldButtons.map { InputEvent.button(down: false, button: $0, x: 0, y: 0) }
            + heldKeys.map { InputEvent.key(usage: $0, down: false) }
        heldButtons.removeAll()
        heldKeys.removeAll()
        if !ups.isEmpty { session.sendInput(ups) }
    }

    // MARK: Chuột

    override func mouseMoved(with event: NSEvent) { move(event, clamping: false) }
    override func mouseDragged(with event: NSEvent) { move(event, clamping: true) }
    override func rightMouseDragged(with event: NSEvent) { move(event, clamping: true) }
    override func otherMouseDragged(with event: NSEvent) { move(event, clamping: true) }

    override func mouseDown(with event: NSEvent) { button(event, down: true, InputButton.left) }
    override func mouseUp(with event: NSEvent) { button(event, down: false, InputButton.left) }
    override func rightMouseDown(with event: NSEvent) { button(event, down: true, InputButton.right) }
    override func rightMouseUp(with event: NSEvent) { button(event, down: false, InputButton.right) }
    override func otherMouseDown(with event: NSEvent) { button(event, down: true, InputButton.other) }
    override func otherMouseUp(with event: NSEvent) { button(event, down: false, InputButton.other) }

    override func scrollWheel(with event: NSEvent) {
        let mods = ViewerEventMapping.modifiers(event.modifierFlags)
        guard let scroll = ViewerEventMapping.scrollEvent(
            deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas, mods: mods
        ) else { return }
        session.sendInput([scroll])
    }

    private func move(_ event: NSEvent, clamping: Bool) {
        guard let point = normalized(event, clamping: clamping) else { return }
        session.sendInput([.move(x: point.x, y: point.y, mods: ViewerEventMapping.modifiers(event.modifierFlags))])
    }

    private func button(_ event: NSEvent, down: Bool, _ button: UInt8) {
        // Nhả nút luôn được ép vào khung để nút đang giữ không bao giờ bị bỏ sót.
        guard let point = normalized(event, clamping: !down || heldButtons.contains(button)) else { return }
        let mods = ViewerEventMapping.modifiers(event.modifierFlags)
        if down { heldButtons.insert(button) } else { heldButtons.remove(button) }
        session.sendInput([
            .move(x: point.x, y: point.y, mods: mods),
            .button(down: down, button: button, x: point.x, y: point.y, clickCount: max(1, event.clickCount), mods: mods),
        ])
    }

    private func normalized(_ event: NSEvent, clamping: Bool) -> (x: Float, y: Float)? {
        let location = convert(event.locationInWindow, from: nil)
        let content = renderer.videoSize ?? bounds.size
        guard let mapper = VideoContentMapper(
            viewWidth: Float(bounds.width), viewHeight: Float(bounds.height),
            contentWidth: Float(content.width), contentHeight: Float(content.height)
        ) else { return nil }
        return mapper.normalize(x: Float(location.x), y: Float(location.y), clamping: clamping)
    }

    // MARK: Bàn phím

    override func keyDown(with event: NSEvent) { key(event, down: true) }
    override func keyUp(with event: NSEvent) { key(event, down: false) }

    override func flagsChanged(with event: NSEvent) {
        session.sendInput(ViewerEventMapping.modifierKeyEvents(macKeyCode: event.keyCode, flags: event.modifierFlags))
    }

    /// ⌘-tổ hợp đi qua đây trước khi tới keyDown; chuyển sang host trừ vài phím giữ lại cho cửa sổ viewer.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, !ViewerEventMapping.staysLocal(macKeyCode: event.keyCode, flags: event.modifierFlags) else { return false }
        return key(event, down: true)
    }

    @discardableResult
    private func key(_ event: NSEvent, down: Bool) -> Bool {
        guard let usage = HidKeyMap.hidUsage(forMacKeyCode: event.keyCode) else { return false }
        if down { heldKeys.insert(usage) } else { heldKeys.remove(usage) }
        session.sendInput([.key(usage: usage, down: down, mods: ViewerEventMapping.modifiers(event.modifierFlags))])
        return true
    }

    /// Đường vào cho `SystemShortcutTap`: phím đã bị chặn khỏi hệ thống Mac viewer.
    func forwardSystemKey(macKeyCode: UInt16, down: Bool, flags: NSEvent.ModifierFlags) {
        guard let usage = HidKeyMap.hidUsage(forMacKeyCode: macKeyCode) else { return }
        session.sendInput([.key(usage: usage, down: down, mods: ViewerEventMapping.modifiers(flags))])
    }
}
