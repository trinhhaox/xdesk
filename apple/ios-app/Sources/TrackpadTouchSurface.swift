import SwiftUI
import UIKit
import XdeskInput

/// Bề mặt đa chạm UIKit: 1 ngón di chuyển / chạm đúp giữ kéo; 2 ngón chạm phải / cuộn; 3 ngón Mission Control & Spaces.
struct TrackpadTouchSurface: UIViewRepresentable {
    let onMove: (Float, Float) -> Void
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    let onScroll: (Float, Float) -> Void
    let onDragStateChange: (Bool) -> Void
    let onThreeFingerShortcut: (UInt16, InputModifiers) -> Void

    func makeUIView(context: Context) -> TouchPadUIView {
        let view = TouchPadUIView()
        updateCallbacks(view)
        return view
    }

    func updateUIView(_ uiView: TouchPadUIView, context: Context) {
        updateCallbacks(uiView)
    }

    private func updateCallbacks(_ view: TouchPadUIView) {
        view.onMove = onMove
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        view.onScroll = onScroll
        view.onDragStateChange = onDragStateChange
        view.onThreeFingerShortcut = onThreeFingerShortcut
    }
}

@MainActor
final class TouchPadUIView: UIView {
    var onMove: (Float, Float) -> Void = { _, _ in }
    var onLeftClick: () -> Void = {}
    var onRightClick: () -> Void = {}
    var onScroll: (Float, Float) -> Void = { _, _ in }
    var onDragStateChange: (Bool) -> Void = { _ in }
    var onThreeFingerShortcut: (UInt16, InputModifiers) -> Void = { _, _ in }

    private var tracked: [ObjectIdentifier: CGPoint] = [:]
    private var maxFingers = 0
    private var gestureStartTime: CFTimeInterval = 0
    private var movedBeyondSlop = false
    private var totalDistance: CGFloat = 0
    private var lastSingleTapUpTime: CFTimeInterval = 0
    private var lastSingleTapPoint: CGPoint = .zero
    private var isTapDragArmed = false
    private var isTapDragActive = false
    private var threeFingerDx: CGFloat = 0
    private var threeFingerDy: CGFloat = 0
    private var threeFingerFired = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let now = CACurrentMediaTime()
        if tracked.isEmpty {
            maxFingers = 0
            movedBeyondSlop = false
            totalDistance = 0
            threeFingerDx = 0
            threeFingerDy = 0
            threeFingerFired = false
            gestureStartTime = now
            if touches.count == 1, let first = touches.first {
                let loc = first.location(in: self)
                let delta = hypot(loc.x - lastSingleTapPoint.x, loc.y - lastSingleTapPoint.y)
                isTapDragArmed = (now - lastSingleTapUpTime <= 0.28) && delta <= 24
            } else {
                isTapDragArmed = false
            }
            isTapDragActive = false
        }
        for touch in touches {
            tracked[ObjectIdentifier(touch)] = touch.location(in: self)
        }
        maxFingers = max(maxFingers, tracked.count)
        if maxFingers > 1 { isTapDragArmed = false }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        var sumDx: CGFloat = 0
        var sumDy: CGFloat = 0
        var count = 0
        for touch in touches {
            let key = ObjectIdentifier(touch)
            guard let prev = tracked[key] else { continue }
            let loc = touch.location(in: self)
            sumDx += loc.x - prev.x
            sumDy += loc.y - prev.y
            tracked[key] = loc
            count += 1
        }
        guard count > 0 else { return }
        let avgDx = sumDx / CGFloat(count)
        let avgDy = sumDy / CGFloat(count)
        totalDistance += hypot(avgDx, avgDy)
        if totalDistance > 8 { movedBeyondSlop = true }
        guard movedBeyondSlop, avgDx != 0 || avgDy != 0 else { return }

        if maxFingers >= 3 {
            guard !threeFingerFired else { return }
            threeFingerDx += avgDx
            threeFingerDy += avgDy
            if hypot(threeFingerDx, threeFingerDy) >= 42 {
                threeFingerFired = true
                if abs(threeFingerDy) >= abs(threeFingerDx) {
                    onThreeFingerShortcut(threeFingerDy < 0 ? 0x52 : 0x51, .control)
                } else {
                    onThreeFingerShortcut(threeFingerDx < 0 ? 0x4F : 0x50, .control)
                }
            }
            return
        }

        if tracked.count >= 2 || maxFingers >= 2 {
            onScroll(Float(avgDx * 1.5), Float(avgDy * 1.5))
        } else {
            if isTapDragArmed && !isTapDragActive {
                isTapDragActive = true
                onDragStateChange(true)
            }
            let w = max(1, bounds.width)
            let h = max(1, bounds.height)
            onMove(Float(avgDx / w * 1.8), Float(avgDy / h * 1.8))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let endedLoc = touches.first?.location(in: self) ?? .zero
        for touch in touches { tracked.removeValue(forKey: ObjectIdentifier(touch)) }
        guard tracked.isEmpty else { return }
        if isTapDragActive {
            isTapDragActive = false
            isTapDragArmed = false
            onDragStateChange(false)
            return
        }
        isTapDragArmed = false
        guard !movedBeyondSlop else { return }
        let elapsed = CACurrentMediaTime() - gestureStartTime
        if maxFingers >= 2 && elapsed <= 0.35 {
            onRightClick()
        } else if maxFingers == 1 && elapsed <= 0.30 {
            lastSingleTapUpTime = CACurrentMediaTime()
            lastSingleTapPoint = endedLoc
            onLeftClick()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { tracked.removeValue(forKey: ObjectIdentifier(touch)) }
        if tracked.isEmpty && isTapDragActive {
            isTapDragActive = false
            onDragStateChange(false)
        }
        isTapDragArmed = false
    }
}
