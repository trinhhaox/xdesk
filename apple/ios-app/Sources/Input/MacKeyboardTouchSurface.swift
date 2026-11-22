import SwiftUI
import UIKit
import XdeskInput

/// Lớp trong suốt phủ lên bàn phím: bắt mọi ngón chạm (đa điểm) và báo xuống/lên ngay lúc chạm, không đợi nhấc tay.
/// Ngón trượt ra khỏi phím vẫn giữ phím đó đến khi nhấc, như bàn phím vật lý.
struct MacKeyboardTouchSurface: UIViewRepresentable {
    let geometry: MacKeyboardGeometry
    let onDown: (Int, UInt16) -> Void
    let onUp: (Int) -> Void

    func makeUIView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: SurfaceView, context: Context) {
        view.geometry = geometry
        view.onDown = onDown
        view.onUp = onUp
    }

    final class SurfaceView: UIView {
        var geometry: MacKeyboardGeometry?
        var onDown: (Int, UInt16) -> Void = { _, _ in }
        var onUp: (Int) -> Void = { _ in }
        private var active: Set<Int> = []

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                guard let usage = geometry?.usage(at: touch.location(in: self)) else { continue }
                let id = ObjectIdentifier(touch).hashValue
                active.insert(id)
                onDown(id, usage)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }

        private func finish(_ touches: Set<UITouch>) {
            for touch in touches {
                let id = ObjectIdentifier(touch).hashValue
                if active.remove(id) != nil { onUp(id) }
            }
        }
    }
}
