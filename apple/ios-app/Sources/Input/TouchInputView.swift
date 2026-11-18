import UIKit
import XdeskInput
import XdeskMedia
import XdeskViewer
import XdeskWire

/// Lớp trong suốt phủ lên video: chạm → `GestureInterpreter` → input gửi host. Chạm vào dải đen letterbox bị bỏ qua.
/// Đồng thời là first responder nhận phím vật lý.
@MainActor
final class TouchInputView: UIView {
    private static let tickInterval: TimeInterval = 0.05

    private let session: ViewerSession
    private let renderer: VideoLayerRenderer
    private lazy var keyboard = HardwareKeyboardHandler { [weak self] in self?.session.sendInput($0) }
    private var interpreter: GestureInterpreter?
    private var touchIds: [ObjectIdentifier: Int] = [:]
    private var nextTouchId = 0
    private var tickTimer: Timer?

    /// Kích thước màn hình host theo điểm (`DisplayConfig` w/h ÷ scale); đổi delta chuẩn hoá thành pixel cuộn.
    var hostPoints = CGSize(width: 1, height: 1)

    init(session: ViewerSession, renderer: VideoLayerRenderer) {
        self.session = session
        self.renderer = renderer
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var canBecomeFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        keyboard.releaseAll()
        return super.resignFirstResponder()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            cancelAllTouches()
            keyboard.releaseAll()
        } else {
            becomeFirstResponder()
        }
    }

    // MARK: Chạm

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !isFirstResponder { becomeFirstResponder() }
        if touchIds.isEmpty { interpreter = makeInterpreter() }
        for touch in touches {
            guard let point = normalized(touch, clamping: false) else { continue }
            touchIds[ObjectIdentifier(touch)] = nextTouchId
            feed(TouchSample(id: nextTouchId, x: point.x, y: point.y, phase: .began, timeMs: Self.ms(touch)))
            nextTouchId += 1
        }
        updateTimer()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { forward(touches, phase: .moved) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { forward(touches, phase: .ended) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { forward(touches, phase: .cancelled) }

    private func forward(_ touches: Set<UITouch>, phase: TouchPhase) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            guard let id = touchIds[key], let point = normalized(touch, clamping: true) else { continue }
            feed(TouchSample(id: id, x: point.x, y: point.y, phase: phase, timeMs: Self.ms(touch)))
            if phase != .moved { touchIds[key] = nil }
        }
        updateTimer()
    }

    private func cancelAllTouches() {
        guard var current = interpreter else { return }
        session.sendInput(touchIds.values.flatMap { current.handle(TouchSample(id: $0, x: 0, y: 0, phase: .cancelled, timeMs: Self.nowMs)) })
        interpreter = current
        touchIds.removeAll()
        updateTimer()
    }

    private func feed(_ sample: TouchSample) {
        guard var current = interpreter else { return }
        let events = current.handle(sample)
        interpreter = current
        session.sendInput(events)
    }

    private func normalized(_ touch: UITouch, clamping: Bool) -> (x: Float, y: Float)? {
        let location = touch.location(in: self)
        let content = renderer.videoSize ?? hostPoints
        guard let mapper = VideoContentMapper(
            viewWidth: Float(bounds.width), viewHeight: Float(bounds.height),
            contentWidth: Float(content.width), contentHeight: Float(content.height)
        ) else { return nil }
        return mapper.normalize(x: Float(location.x), y: Float(location.y), clamping: clamping)
    }

    private func makeInterpreter() -> GestureInterpreter {
        GestureInterpreter(config: GestureConfig(surfaceWidth: Float(hostPoints.width), surfaceHeight: Float(hostPoints.height)))
    }

    // MARK: Tick 50 ms (giữ lâu → click phải)

    private func updateTimer() {
        if touchIds.isEmpty {
            tickTimer?.invalidate()
            tickTimer = nil
        } else if tickTimer == nil {
            tickTimer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
    }

    private func tick() {
        guard var current = interpreter else { return }
        let events = current.tick(nowMs: Self.nowMs)
        interpreter = current
        session.sendInput(events)
    }

    private static var nowMs: Int64 { Int64(ProcessInfo.processInfo.systemUptime * 1000) }
    private static func ms(_ touch: UITouch) -> Int64 { Int64(touch.timestamp * 1000) }

    // MARK: Bàn phím vật lý

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !keyboard.pressesBegan(presses) { super.pressesBegan(presses, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !keyboard.pressesEnded(presses) { super.pressesEnded(presses, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        keyboard.releaseAll()
        super.pressesCancelled(presses, with: event)
    }
}
