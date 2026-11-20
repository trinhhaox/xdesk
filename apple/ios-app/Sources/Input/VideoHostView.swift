import UIKit
import XdeskInput

/// Chứa video + lớp nhập liệu + ô gõ ẩn. Khi bàn phím mở, video được dịch lên (không thu nhỏ) để vùng người dùng vừa chạm
/// luôn nằm trên bàn phím; dịch cùng thời lượng/đường cong với bàn phím nên mượt. Vẽ thêm con trỏ cục bộ ở chế độ trackpad.
@MainActor
final class VideoHostView: UIView {
    private static let cursorHideDelay: Duration = .seconds(1.5)

    private let container = UIView()
    private let videoLayer: CALayer
    let touchView: TouchInputView
    private let controller: TextComposerController
    private let composer: ComposerInputView
    private let cursorLayer = CAShapeLayer()
    private var obscuredHeight: CGFloat = 0
    private var keyboardObserver: NSObjectProtocol?
    private var hideCursorTask: Task<Void, Never>?
    /// Khoảng chừa trên bàn phím cho dòng đang gõ: đủ chỗ cho bong bóng xem trước chữ Telex (~40 điểm) nằm ngay trên bàn phím.
    private static let focusMargin: Float = 64
    private var zoomController: VideoZoomController?
    private let zoomState: VideoZoomState

    /// Bản sao "Giống màn hình Mac": bật zoom/kéo và lấy kích thước Mac từ video. Tắt = về vừa khung.
    var zoomEnabled: Bool {
        get { zoomController?.enabled ?? false }
        set {
            touchView.nativeMac = newValue
            zoomController?.enabled = newValue
        }
    }

    init(videoLayer: CALayer, touchView: TouchInputView, controller: TextComposerController, zoomState: VideoZoomState) {
        self.zoomState = zoomState
        self.videoLayer = videoLayer
        self.touchView = touchView
        self.controller = controller
        composer = ComposerInputView(controller: controller)
        super.init(frame: .zero)
        backgroundColor = .black
        container.layer.addSublayer(videoLayer)
        configureCursor()
        addSubview(container)
        addSubview(touchView)
        addSubview(composer)
        touchView.onCursor = { [weak self] in self?.showCursor($0) }
        touchView.onSequenceEnded = { [weak self] in self?.applyPan(duration: 0.2, options: .curveEaseInOut) }
        touchView.onViewportChanged = { [weak self] in self?.viewportChanged() }
        touchView.onKeyboardRequest = { [weak controller] in
            Haptics.light()
            controller?.isActive = true
        }
        zoomController = VideoZoomController(host: self, touchView: touchView) { [weak self] in self?.viewportChanged() }
        zoomState.reset = { [weak self] in self?.zoomController?.reset() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        container.bounds = CGRect(origin: .zero, size: bounds.size)
        container.center = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = container.bounds
        CATransaction.commit()
        touchView.frame = bounds
        zoomController?.reclamp()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            keyboardObserver.map(NotificationCenter.default.removeObserver)
            keyboardObserver = nil
            return
        }
        guard keyboardObserver == nil else { return }
        keyboardObserver = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
            let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
            let curve = (note.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt) ?? 7
            MainActor.assumeIsolated { self?.keyboardFrameChanged(frame, duration: duration, curve: curve) }
        }
    }

    /// Mở/đóng bàn phím theo `TextComposerController.isActive`.
    func syncKeyboard(active: Bool) {
        touchView.keyboardActive = active
        if active {
            if !composer.isFirstResponder { composer.becomeFirstResponder() }
        } else {
            if composer.isFirstResponder { composer.resignFirstResponder() }
            if !touchView.isFirstResponder { touchView.becomeFirstResponder() }
        }
    }

    // MARK: Dịch video theo bàn phím

    private func keyboardFrameChanged(_ screenFrame: CGRect, duration: TimeInterval, curve: UInt) {
        let space = window?.screen.coordinateSpace
        let local = space.map { convert(screenFrame, from: $0) } ?? screenFrame
        obscuredHeight = max(0, bounds.maxY - local.minY)
        controller.obscuredHeight = obscuredHeight
        applyPan(duration: duration, options: UIView.AnimationOptions(rawValue: curve << 16))
    }

    private func applyPan(duration: TimeInterval, options: UIView.AnimationOptions) {
        let pan = currentPan()
        touchView.panY = pan
        UIView.animate(withDuration: duration, delay: 0, options: options.union(.beginFromCurrentState)) {
            self.container.transform = self.containerTransform(pan: pan)
        }
    }

    /// Zoom quanh tâm view rồi kéo (`translation`), cuối cùng đẩy lên theo bàn phím.
    private func containerTransform(pan: CGFloat) -> CGAffineTransform {
        let viewport = touchView.viewport
        let zoom = CGFloat(viewport.zoom)
        return CGAffineTransform(translationX: CGFloat(viewport.translationX), y: CGFloat(viewport.translationY) - pan).scaledBy(x: zoom, y: zoom)
    }

    private func viewportChanged() {
        zoomState.isZoomed = !touchView.viewport.isIdentity
        applyPan(duration: 0, options: [])
    }

    private func currentPan() -> CGFloat {
        guard obscuredHeight > 0, let rect = touchView.contentRect, let focus = touchView.focusNormalizedY,
              let mapper = touchView.mapper() else { return 0 }
        let viewport = touchView.viewport
        let focusY = viewport.toView(x: 0, y: Float(rect.minY + CGFloat(focus) * rect.height), in: mapper).y
        let videoBottom = viewport.toView(x: 0, y: Float(rect.maxY), in: mapper).y
        return CGFloat(VideoPan.offset(focusY: focusY, viewHeight: Float(bounds.height), obscuredHeight: Float(obscuredHeight), videoBottom: videoBottom, margin: Self.focusMargin))
    }

    // MARK: Con trỏ cục bộ

    private func configureCursor() {
        let path = UIBezierPath()
        path.move(to: .zero)
        for (x, y) in [(0.0, 17.0), (4.2, 13.2), (7.0, 19.5), (9.8, 18.3), (7.0, 12.2), (12.0, 12.2)] { path.addLine(to: CGPoint(x: x, y: y)) }
        path.close()
        cursorLayer.path = path.cgPath
        cursorLayer.bounds = CGRect(x: 0, y: 0, width: 12, height: 20)
        cursorLayer.anchorPoint = .zero
        cursorLayer.fillColor = UIColor.white.cgColor
        cursorLayer.strokeColor = UIColor.black.withAlphaComponent(0.85).cgColor
        cursorLayer.lineWidth = 1.2
        cursorLayer.opacity = 0
        container.layer.addSublayer(cursorLayer)
    }

    private func showCursor(_ point: CGPoint?) {
        hideCursorTask?.cancel()
        guard let point else { cursorLayer.opacity = 0; return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer.position = point
        // Con trỏ nằm trong container đã zoom: nghịch đảo để giữ cỡ cố định trên màn hình.
        let inverse = 1 / CGFloat(touchView.viewport.zoom)
        cursorLayer.setAffineTransform(CGAffineTransform(scaleX: inverse, y: inverse))
        cursorLayer.opacity = 1
        CATransaction.commit()
        hideCursorTask = Task { [weak self] in
            try? await Task.sleep(for: Self.cursorHideDelay)
            guard !Task.isCancelled else { return }
            self?.cursorLayer.opacity = 0
        }
    }
}
