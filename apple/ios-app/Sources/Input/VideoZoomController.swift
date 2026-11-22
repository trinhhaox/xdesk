import Observation
import UIKit
import XdeskInput

/// Trạng thái zoom cho SwiftUI (nút "Vừa khung" ở thanh công cụ chỉ hiện khi đang zoom).
@MainActor
@Observable
final class VideoZoomState {
    var isZoomed = false
    @ObservationIgnored var reset: (() -> Void)?
}

/// Zoom/kéo video ở kiểu Bản sao "Giống màn hình Mac": chụm hai ngón để zoom (tâm chụm cũng kéo video), ba ngón để kéo khi đã zoom.
/// Cử chỉ chỉ cập nhật `TouchInputView.viewport`; chạm bình thường vẫn đi qua `PointerEngine` với toạ độ đã đổi ngược.
/// Khi cử chỉ nhận ra, UIKit huỷ chạm đang gửi cho `TouchInputView` nên không có click lạc.
@MainActor
final class VideoZoomController: NSObject, UIGestureRecognizerDelegate {
    private unowned let host: UIView
    private let touchView: TouchInputView
    private let onChange: () -> Void
    private let pinch = UIPinchGestureRecognizer()
    private let pan = UIPanGestureRecognizer()
    private var lastFocus = CGPoint.zero

    var enabled = false {
        didSet {
            updateRecognizers()
            if !enabled { reset() }
        }
    }

    /// Đang chỉnh cửa sổ: tạm tắt cử chỉ zoom/kéo nhưng giữ nguyên mức zoom hiện tại để thoát ra là như cũ.
    var suspended = false { didSet { updateRecognizers() } }

    private func updateRecognizers() {
        pinch.isEnabled = enabled && !suspended
        pan.isEnabled = enabled && !suspended
    }

    init(host: UIView, touchView: TouchInputView, onChange: @escaping () -> Void) {
        self.host = host
        self.touchView = touchView
        self.onChange = onChange
        super.init()
        pinch.addTarget(self, action: #selector(handlePinch))
        pan.addTarget(self, action: #selector(handlePan))
        pan.minimumNumberOfTouches = 3
        pan.maximumNumberOfTouches = 3
        for recognizer in [pinch, pan] as [UIGestureRecognizer] {
            recognizer.delegate = self
            recognizer.isEnabled = false
            host.addGestureRecognizer(recognizer)
        }
    }

    func reset() { apply(.identity) }

    /// Sau xoay máy/đổi kích thước: ép lại cho hợp hình học mới.
    func reclamp() {
        guard let mapper = touchView.mapper() else { return }
        apply(touchView.viewport.clamped(in: mapper))
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let mapper = touchView.mapper() else { return }
        let point = gesture.location(in: host)
        switch gesture.state {
        case .began: lastFocus = point
        case .changed:
            let focus = (x: Float(point.x), y: Float(point.y + touchView.panY))
            var next = touchView.viewport.panned(dx: Float(point.x - lastFocus.x), dy: Float(point.y - lastFocus.y), in: mapper)
            next = next.zoomed(by: Float(gesture.scale), around: focus, in: mapper)
            gesture.scale = 1
            lastFocus = point
            apply(next)
        default: break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed, let mapper = touchView.mapper() else { return }
        let delta = gesture.translation(in: host)
        gesture.setTranslation(.zero, in: host)
        apply(touchView.viewport.panned(dx: Float(delta.x), dy: Float(delta.y), in: mapper))
    }

    private func apply(_ viewport: VideoViewport) {
        guard viewport != touchView.viewport else { return }
        touchView.viewport = viewport
        onChange()
    }

    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
