import Foundation
import XdeskWire

public enum WindowCorner: CaseIterable, Sendable { case topLeft, topRight, bottomLeft, bottomRight }

/// Toán thuần cho cử chỉ chỉnh cửa sổ: dự đoán frame phía viewer rồi đổi độ chênh thành lệnh `window.adjust`.
/// Mọi số theo hệ toạ độ host (xem `WindowSpace`). Host vẫn kẹp lại lần cuối; viewer kẹp trước để khung vẽ không "nhảy".
public enum WindowGestureMath {
    public static let minWidth = 200.0
    public static let minHeight = 150.0
    /// Độ chênh nhỏ hơn mức này (điểm) thì chưa gửi, dồn sang khung hình sau.
    public static let epsilon = 0.25

    public static func moved(_ frame: WindowFrame, dx: Double, dy: Double) -> WindowFrame {
        WindowFrame(x: frame.x + dx, y: frame.y + dy, w: frame.w, h: frame.h)
    }

    /// Chụm/mở quanh tâm: một hệ số chung cho cả hai chiều, kẹp trong [tối thiểu, `maxWidth`×`maxHeight`] (tối thiểu thắng).
    public static func pinched(_ frame: WindowFrame, scale: Double, maxWidth: Double, maxHeight: Double) -> WindowFrame {
        guard scale.isFinite, scale > 0 else { return frame }
        let lower = max(minWidth / frame.w, minHeight / frame.h)
        let upper = min(maxWidth / frame.w, maxHeight / frame.h)
        let factor = max(lower, min(scale, upper))
        let w = frame.w * factor, h = frame.h * factor
        return WindowFrame(x: frame.centerX - w / 2, y: frame.centerY - h / 2, w: w, h: h)
    }

    /// Kéo một góc: góc đối diện đứng yên, cạnh kẹp ở kích thước tối thiểu.
    public static func cornerDragged(_ frame: WindowFrame, corner: WindowCorner, dx: Double, dy: Double) -> WindowFrame {
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        let w = max(minWidth, left ? frame.w - dx : frame.w + dx)
        let h = max(minHeight, top ? frame.h - dy : frame.h + dy)
        return WindowFrame(x: left ? frame.x + frame.w - w : frame.x, y: top ? frame.y + frame.h - h : frame.y, w: w, h: h)
    }

    /// Lệnh cần gửi để host từ `old` tới `new`. Host giữ tâm khi `resize`, nên đổi cỡ trước rồi `move` phần tâm lệch.
    /// `applied` là frame host sẽ có nếu mọi lệnh được áp dụng (phần chưa gửi vì quá nhỏ được dồn lại cho lần sau).
    public static func plan(windowId: UInt32, from old: WindowFrame, to new: WindowFrame) -> (ops: [WindowAdjust], applied: WindowFrame) {
        var ops: [WindowAdjust] = []
        var applied = old
        if abs(new.w - old.w) >= epsilon || abs(new.h - old.h) >= epsilon {
            ops.append(.resize(windowId: windowId, w: new.w, h: new.h))
            applied = WindowFrame(x: old.centerX - new.w / 2, y: old.centerY - new.h / 2, w: new.w, h: new.h)
        }
        let dx = new.centerX - applied.centerX, dy = new.centerY - applied.centerY
        if abs(dx) >= epsilon || abs(dy) >= epsilon {
            ops.append(.move(windowId: windowId, dx: dx, dy: dy))
            applied.x += dx
            applied.y += dy
        }
        return (ops, applied)
    }

    /// Frame dưới ngón tay: góc nào trong bán kính `radius` (điểm view) quanh `point`, ưu tiên góc gần nhất.
    public static func corner(at point: (x: Double, y: Double), corners: [WindowCorner: (x: Double, y: Double)], radius: Double) -> WindowCorner? {
        corners
            .map { (corner: $0.key, distance: hypot($0.value.x - point.x, $0.value.y - point.y)) }
            .filter { $0.distance <= radius }
            .min { $0.distance < $1.distance }?.corner
    }
}

extension WindowFrame {
    var centerX: Double { x + w / 2 }
    var centerY: Double { y + h / 2 }
}
