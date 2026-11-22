import UIKit
import XdeskInput
import XdeskWire

/// Lớp phủ trên video khi chỉnh cửa sổ: nhận chạm (chọn), kéo 1 ngón (dời), chụm 2 ngón / kéo góc (đổi cỡ) và vẽ khung viền xanh
/// + tên app + 4 tay cầm góc. Chạm → toạ độ host qua `WindowSpace` (cùng phép đổi với chạm trực tiếp, kể cả letterbox/zoom).
@MainActor
final class WindowAdjustOverlayView: UIView, UIGestureRecognizerDelegate {
    private static let handleDiameter: CGFloat = 28
    private static let handleHitRadius: Double = 28
    private static let accent = UIColor(red: 0x5B / 255, green: 0x8C / 255, blue: 1, alpha: 1)

    private enum Drag { case move, corner(WindowCorner) }

    private let controller: WindowAdjustController
    private let space: () -> WindowSpace?
    private let outline = CAShapeLayer()
    private let handles: [WindowCorner: CALayer]
    private let nameLabel = UILabel()
    private var drag: Drag?
    private var downPoint = CGPoint.zero
    private var ticker: DisplayLinkTicker?

    init(controller: WindowAdjustController, space: @escaping () -> WindowSpace?) {
        self.controller = controller
        self.space = space
        handles = Dictionary(uniqueKeysWithValues: WindowCorner.allCases.map { ($0, CALayer()) })
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isHidden = true
        outline.fillColor = Self.accent.withAlphaComponent(0.12).cgColor
        outline.strokeColor = Self.accent.cgColor
        outline.lineWidth = 2
        layer.addSublayer(outline)
        for handle in handles.values {
            handle.bounds = CGRect(x: 0, y: 0, width: Self.handleDiameter, height: Self.handleDiameter)
            handle.cornerRadius = Self.handleDiameter / 2
            handle.backgroundColor = UIColor.white.cgColor
            handle.borderColor = Self.accent.cgColor
            handle.borderWidth = 3
            layer.addSublayer(handle)
        }
        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.textAlignment = .center
        nameLabel.backgroundColor = Self.accent
        nameLabel.layer.cornerRadius = 8
        nameLabel.clipsToBounds = true
        addSubview(nameLabel)
        installGestures()
        controller.onChange = { [weak self] in self?.redraw() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func installGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        for recognizer in [tap, pan, pinch] as [UIGestureRecognizer] {
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        redraw()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first { downPoint = touch.location(in: self) }
        super.touchesBegan(touches, with: event)
    }

    // MARK: Vẽ

    func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard controller.isActive, let frame = controller.frame, let space = space() else {
            outline.path = nil
            handles.values.forEach { $0.isHidden = true }
            nameLabel.isHidden = true
            return
        }
        let rect = space.viewRect(frame)
        outline.path = UIBezierPath(roundedRect: rect, cornerRadius: 6).cgPath
        for (corner, handle) in handles {
            handle.position = cornerPoints(rect)[corner] ?? .zero
            handle.isHidden = !controller.resizable
        }
        nameLabel.text = "  \(controller.appName ?? "Cửa sổ")  "
        nameLabel.sizeToFit()
        let size = CGSize(width: nameLabel.bounds.width, height: 22)
        let above = rect.minY - size.height - 8
        let x = min(max(rect.minX, 4), max(4, bounds.width - size.width - 4))
        nameLabel.frame = CGRect(origin: CGPoint(x: x, y: above >= 4 ? above : rect.minY + 8), size: size)
        nameLabel.isHidden = false
    }

    private func cornerPoints(_ rect: CGRect) -> [WindowCorner: CGPoint] {
        [.topLeft: CGPoint(x: rect.minX, y: rect.minY), .topRight: CGPoint(x: rect.maxX, y: rect.minY),
         .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY), .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)]
    }

    // MARK: Cử chỉ

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let space = space() else { return }
        let point = gesture.location(in: self)
        guard let wire = space.toWire(x: point.x, y: point.y) else { return }
        controller.pick(x: wire.x, y: wire.y)
    }

    private func hit(at point: CGPoint) -> Drag? {
        guard let frame = controller.frame, let space = space() else { return nil }
        let rect = space.viewRect(frame)
        if controller.resizable {
            let corners = cornerPoints(rect).mapValues { (x: Double($0.x), y: Double($0.y)) }
            if let corner = WindowGestureMath.corner(at: (x: point.x, y: point.y), corners: corners, radius: Self.handleHitRadius) { return .corner(corner) }
        }
        return rect.contains(point) ? .move : nil
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UIPanGestureRecognizer { return controller.hasSelection && hit(at: downPoint) != nil }
        if gestureRecognizer is UIPinchGestureRecognizer { return controller.hasSelection && controller.resizable }
        return true
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            drag = hit(at: downPoint)
            beginGesture()
        case .changed:
            guard let drag, let frame = controller.frame, let space = space() else { return }
            let t = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)
            let delta = space.wireDelta(viewDx: t.x, viewDy: t.y)
            switch drag {
            case .move: controller.predict(WindowGestureMath.moved(frame, dx: delta.dx, dy: delta.dy))
            case .corner(let corner): controller.predict(WindowGestureMath.cornerDragged(frame, corner: corner, dx: delta.dx, dy: delta.dy))
            }
        case .ended, .cancelled, .failed:
            drag = nil
            endGesture()
        default: break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began: beginGesture()
        case .changed:
            guard let frame = controller.frame, let space = space() else { return }
            let scale = Double(gesture.scale)
            gesture.scale = 1
            controller.predict(WindowGestureMath.pinched(frame, scale: scale, maxWidth: space.wireWidth, maxHeight: space.wireHeight))
        case .ended, .cancelled, .failed: endGesture()
        default: break
        }
    }

    private func beginGesture() {
        controller.beginGesture()
        ticker = DisplayLinkTicker { [weak controller] in controller?.flush() }
    }

    private func endGesture() {
        ticker?.stop()
        ticker = nil
        controller.endGesture()
    }
}
