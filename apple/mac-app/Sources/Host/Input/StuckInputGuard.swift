import CoreGraphics

/// Chống kẹt nút/phím: nhả hết khi phiên kết thúc/viewer ngắt (`releaseAll`), hoặc khi đang giữ mà
/// không nhận gì suốt `idleTimeoutMs` (viewer gửi heartbeat mỗi 250 ms khi còn giữ, nên im lặng = mất gói/mất mạng).
final class StuckInputGuard {
    static let idleTimeoutMs: Int64 = 1000

    private let injector: any EventInjecting
    private var buttons: [MouseButton] = []
    private var keys: [CGKeyCode] = []
    private var lastPoint = CGPoint.zero
    private var lastActivityMs: Int64 = 0

    init(injector: any EventInjecting) { self.injector = injector }

    var isHolding: Bool { !buttons.isEmpty || !keys.isEmpty }
    /// Nút ưu tiên cho sự kiện kéo (trái trước).
    var primaryButton: MouseButton? { buttons.first }

    func noteActivity(nowMs: Int64) { lastActivityMs = nowMs }

    func moved(to point: CGPoint) { lastPoint = point }

    func buttonDown(_ button: MouseButton, at point: CGPoint) {
        lastPoint = point
        if !buttons.contains(button) { buttons.append(button) }
    }

    /// false nếu nút không đang giữ (up thừa: bỏ qua).
    func buttonUp(_ button: MouseButton, at point: CGPoint) -> Bool {
        lastPoint = point
        guard let index = buttons.firstIndex(of: button) else { return false }
        buttons.remove(at: index)
        return true
    }

    func keyDown(_ code: CGKeyCode) {
        if !keys.contains(code) { keys.append(code) }
    }

    func keyUp(_ code: CGKeyCode) -> Bool {
        guard let index = keys.firstIndex(of: code) else { return false }
        keys.remove(at: index)
        return true
    }

    /// Gọi định kỳ; trả true nếu vừa nhả vì im lặng quá lâu.
    @discardableResult
    func tick(nowMs: Int64) -> Bool {
        guard isHolding, nowMs - lastActivityMs > Self.idleTimeoutMs else { return false }
        releaseAll()
        return true
    }

    func releaseAll() {
        let heldButtons = buttons, heldKeys = keys
        buttons.removeAll()
        keys.removeAll()
        for button in heldButtons { injector.mouseButton(button, down: false, at: lastPoint, clickCount: 1, flags: []) }
        for code in heldKeys.reversed() { injector.key(code, down: false, flags: []) }
    }
}
