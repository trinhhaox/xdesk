import UIKit
import XdeskInput
import XdeskMedia
import XdeskViewer
import XdeskWire

/// Lớp trong suốt phủ lên video: chạm → `PointerEngine` (trực tiếp hoặc trackpad) → input gửi host. Ở chế độ trực tiếp, chạm vào
/// dải đen letterbox bị bỏ qua. Đồng thời là first responder nhận phím vật lý (trừ lúc ô gõ ảo đang giữ bàn phím).
@MainActor
final class TouchInputView: UIView {
    static let tickInterval: TimeInterval = 0.05
    private static let cursorMargin: Float = 40

    let session: ViewerSession
    private let renderer: VideoLayerRenderer
    lazy var keyboard = HardwareKeyboardHandler { [weak self] in self?.session.sendInput($0) }
    var engine: PointerEngine?
    private var engineStale = true
    private var lastTouch: (x: Float, y: Float)?
    var touchIds: [ObjectIdentifier: Int] = [:]
    private var nextTouchId = 0
    var tickTimer: Timer?

    /// Kích thước màn hình host theo điểm (`DisplayConfig` w/h ÷ scale); đổi delta chuẩn hoá thành pixel cuộn.
    var hostPoints = CGSize(width: 1, height: 1) { didSet { if oldValue != hostPoints { engineStale = true } } }
    /// `display.config.scale`: kích thước video (px) ÷ scale = hệ toạ độ của `window.pick`/`window.adjust`.
    var configScale = 1.0
    var pointer = PointerSettings() { didSet { if oldValue != pointer { engineStale = true } } }
    /// Bản sao "Giống màn hình Mac": kích thước Mac lấy từ video (không phải từ cấu hình) và video có thể zoom/kéo.
    var nativeMac = false { didSet { if oldValue != nativeMac { engineStale = true } } }
    /// Zoom/kéo hiện tại; chạm được đổi ngược về toạ độ video chưa zoom trước khi vào `VideoContentMapper`.
    var viewport = VideoViewport.identity
    /// Video đang dịch lên bao nhiêu điểm (bàn phím mở); cộng vào y của ngón để ra toạ độ video.
    var panY: CGFloat = 0
    /// Bàn phím ảo đang giữ first responder: đừng giành lại khi chạm.
    var keyboardActive = false
    /// Vị trí con trỏ cục bộ (toạ độ view chưa dịch) ở chế độ trackpad.
    var onCursor: ((CGPoint?) -> Void)?
    /// Viewport đổi do con trỏ trackpad chạy ra mép: view cha cập nhật transform.
    var onViewportChanged: (() -> Void)?
    /// Vừa nhả ngón cuối: nơi người dùng chạm đã đổi, tính lại độ dịch.
    var onSequenceEnded: (() -> Void)?
    /// Người dùng chạm 2 lần vào chỗ cần gõ: mở bàn phím.
    var onKeyboardRequest: (() -> Void)?

    /// Khung video thật trong view (chưa dịch); nil khi chưa biết kích thước.
    var contentRect: CGRect? {
        mapper().map { CGRect(x: CGFloat($0.originX), y: CGFloat($0.originY), width: CGFloat($0.width), height: CGFloat($0.height)) }
    }

    /// Chiều dọc (0…1 trên video) của vùng người dùng vừa thao tác: con trỏ (trackpad) hoặc điểm chạm cuối (trực tiếp).
    var focusNormalizedY: Float? { engine?.cursor?.y ?? lastTouch?.y }

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
        } else if !keyboardActive {
            becomeFirstResponder()
        }
    }

    // MARK: Chạm

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !isFirstResponder, !keyboardActive { becomeFirstResponder() }
        if touchIds.isEmpty {
            rebuildEngineIfNeeded()
            updateTouchScale()
        }
        for touch in touches {
            guard let point = normalized(touch, clamping: false) else { continue }
            lastTouch = point
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
            if phase == .ended { lastTouch = point }
            feed(TouchSample(id: id, x: point.x, y: point.y, phase: phase, timeMs: Self.ms(touch)))
            if phase != .moved { touchIds[key] = nil }
        }
        updateTimer()
        if touchIds.isEmpty { onSequenceEnded?() }
    }

    private func cancelAllTouches() {
        guard var current = engine else { return }
        session.sendInput(touchIds.values.flatMap { current.handle(TouchSample(id: $0, x: 0, y: 0, phase: .cancelled, timeMs: Self.nowMs)) })
        engine = current
        touchIds.removeAll()
        updateTimer()
    }

    private func feed(_ sample: TouchSample) {
        guard var current = engine else { return }
        let events = current.handle(sample)
        let keyboardRequested = current.takeKeyboardRequest()
        engine = current
        session.sendInput(events)
        if keyboardRequested { onKeyboardRequest?() }
        if let cursor = current.cursor {
            revealCursor(cursor)
            onCursor?(viewPoint(cursor))
        }
    }

    func mapper() -> VideoContentMapper? {
        let content = renderer.videoSize ?? hostPoints
        return VideoContentMapper(
            viewWidth: Float(bounds.width), viewHeight: Float(bounds.height),
            contentWidth: Float(content.width), contentHeight: Float(content.height)
        )
    }

    /// Hệ toạ độ chỉnh cửa sổ (luồng video đang xem ÷ scale) + phép đổi từ view qua letterbox/zoom hiện tại.
    func windowSpace() -> WindowSpace? {
        guard let mapper = mapper(), configScale > 0 else { return nil }
        let size = renderer.videoSize.map { CGSize(width: $0.width / configScale, height: $0.height / configScale) } ?? hostPoints
        return WindowSpace(wireWidth: size.width, wireHeight: size.height, mapper: mapper, viewport: viewport)
    }

    /// Trackpad chỉ cần độ dời nên không ép vào khung video; trực tiếp bỏ qua chạm ngoài khung.
    private func normalized(_ touch: UITouch, clamping: Bool) -> (x: Float, y: Float)? {
        let location = touch.location(in: self)
        guard let mapper = mapper() else { return nil }
        let x = Float(location.x), y = Float(location.y + panY)
        if engine?.cursor != nil {
            let relative = viewport.toBaseIgnoringPan(x: x, y: y, in: mapper)
            return mapper.normalizeUnbounded(x: relative.x, y: relative.y)
        }
        let base = viewport.toBase(x: x, y: y, in: mapper)
        return mapper.normalize(x: base.x, y: base.y, clamping: clamping)
    }

    /// Đang zoom ở chế độ con trỏ: con trỏ chạy ra mép thì kéo video theo để luôn thấy nó.
    private func revealCursor(_ cursor: (x: Float, y: Float)) {
        guard !viewport.isIdentity, let mapper = mapper() else { return }
        let base = (x: mapper.originX + cursor.x * mapper.width, y: mapper.originY + cursor.y * mapper.height)
        let next = viewport.revealing(base: base, margin: Self.cursorMargin, in: mapper)
        guard next != viewport else { return }
        viewport = next
        onViewportChanged?()
    }

    private func viewPoint(_ normalized: (x: Float, y: Float)) -> CGPoint? {
        mapper().map { CGPoint(x: CGFloat($0.originX + normalized.x * $0.width), y: CGFloat($0.originY + normalized.y * $0.height)) }
    }

    /// Kích thước màn hình Mac theo điểm: từ cấu hình, hoặc (Giống màn hình Mac) từ video ÷ 2 vì màn hình Retina.
    var surfacePoints: CGSize {
        guard nativeMac, let video = renderer.videoSize else { return hostPoints }
        return CGSize(width: video.width / 2, height: video.height / 2)
    }

    private func rebuildEngineIfNeeded() {
        guard engine == nil || engineStale else { return }
        let surface = surfacePoints
        engine = PointerEngine(settings: pointer, surfaceWidth: Float(surface.width), surfaceHeight: Float(surface.height), cursor: engine?.cursor)
        engineStale = false
    }
}
