import CoreGraphics
import XdeskWire

/// Quy đổi giữa toạ độ viewer (điểm của khung hình video đang xem) và toạ độ màn hình Mac của màn hình đang chiếu
/// (hệ CG/AX: gốc trên-trái màn hình chính, y xuống). Điểm đi qua `CoordinateMapper` giống hệt input con trỏ.
struct WindowViewport: Equatable {
    /// `CGDisplayBounds` của màn hình đang chiếu.
    let displayBounds: CGRect
    /// Kích thước khung video theo điểm viewer (`pixel / display.config.scale`).
    let viewerSize: CGSize

    var isValid: Bool {
        displayBounds.width > 0 && displayBounds.height > 0 && viewerSize.width > 0 && viewerSize.height > 0
    }

    private var scaleX: CGFloat { displayBounds.width / viewerSize.width }
    private var scaleY: CGFloat { displayBounds.height / viewerSize.height }

    func screenPoint(x: Double, y: Double) -> CGPoint {
        let bounds = displayBounds
        let nx = Float(x / Double(viewerSize.width)), ny = Float(y / Double(viewerSize.height))
        return CoordinateMapper(bounds: { bounds }).point(x: nx, y: ny)
    }

    func screenDelta(dx: Double, dy: Double) -> CGPoint { CGPoint(x: dx * scaleX, y: dy * scaleY) }

    func screenSize(w: Double, h: Double) -> CGSize { CGSize(width: w * scaleX, height: h * scaleY) }

    func viewerFrame(fromScreen rect: CGRect) -> WindowFrame {
        WindowFrame(
            x: (rect.minX - displayBounds.minX) / scaleX, y: (rect.minY - displayBounds.minY) / scaleY,
            w: rect.width / scaleX, h: rect.height / scaleY)
    }
}

/// Hình học thuần của chỉnh cửa sổ (toạ độ AX, đơn vị điểm màn hình). `visible` = vùng hiển thị của màn hình đang chiếu.
enum WindowAdjustGeometry {
    static let minSize = CGSize(width: 200, height: 150)
    /// "Giữa" = 70% vùng hiển thị.
    static let centerFraction: CGFloat = 0.7

    /// Kích thước kẹp trong `[minSize, visible]` (vùng hiển thị nhỏ hơn cỡ tối thiểu thì theo vùng hiển thị).
    static func clampedSize(_ size: CGSize, in visible: CGRect) -> CGSize {
        CGSize(
            width: min(max(size.width, min(minSize.width, visible.width)), visible.width),
            height: min(max(size.height, min(minSize.height, visible.height)), visible.height))
    }

    /// Dời `frame` cho nằm trọn trong `visible` (giữ nguyên cỡ; cửa sổ lớn hơn vùng hiển thị thì dính cạnh trên-trái).
    static func clampedOrigin(_ frame: CGRect, in visible: CGRect) -> CGRect {
        var result = frame
        result.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
        result.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
        return result
    }

    static func moved(_ frame: CGRect, by delta: CGPoint, in visible: CGRect) -> CGRect {
        clampedOrigin(frame.offsetBy(dx: delta.x, dy: delta.y), in: visible)
    }

    /// Đổi sang `size` tuyệt đối: giữ tâm; nếu tâm làm cửa sổ tràn ra ngoài vùng hiển thị thì giữ góc trên-trái (rồi kẹp).
    static func resized(_ frame: CGRect, to size: CGSize, in visible: CGRect) -> CGRect {
        let newSize = clampedSize(size, in: visible)
        let centred = CGRect(x: frame.midX - newSize.width / 2, y: frame.midY - newSize.height / 2, width: newSize.width, height: newSize.height)
        let candidate = visible.contains(centred) ? centred : CGRect(origin: frame.origin, size: newSize)
        return clampedOrigin(candidate, in: visible)
    }

    /// `canResize == false`: chỉ đổi vị trí (giữ cỡ hiện tại, đặt theo tâm của khung đích).
    static func preset(_ preset: WindowPreset, current: CGRect, visible: CGRect, original: CGRect?, canResize: Bool) -> CGRect {
        let target: CGRect
        switch preset {
        case .fill: target = visible
        case .left: target = CGRect(x: visible.minX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case .right: target = CGRect(x: visible.midX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case .center:
            let size = CGSize(width: visible.width * centerFraction, height: visible.height * centerFraction)
            target = CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
        case .restore: target = original ?? current
        }
        guard canResize else {
            return clampedOrigin(CGRect(x: target.midX - current.width / 2, y: target.midY - current.height / 2, width: current.width, height: current.height), in: visible)
        }
        let size = clampedSize(target.size, in: visible)
        return clampedOrigin(CGRect(origin: target.origin, size: size), in: visible)
    }
}

/// Gộp các `window.adjust` đến liên tiếp: `move` cộng dồn, `resize` giữ mới nhất, `preset` thay thế mọi thứ trước đó của cùng cửa sổ.
/// Thứ tự giữa các loại được giữ (move rồi resize rồi move vẫn ra 3 bước).
struct WindowAdjustAccumulator {
    private(set) var pending: [WindowAdjust] = []

    var isEmpty: Bool { pending.isEmpty }

    mutating func add(_ adjust: WindowAdjust) {
        if adjust.op == .preset { pending.removeAll { $0.windowId == adjust.windowId } }
        if let last = pending.last, last.windowId == adjust.windowId, last.op == adjust.op {
            switch adjust.op {
            case .move:
                pending[pending.count - 1] = .move(
                    windowId: adjust.windowId, dx: (last.dx ?? 0) + (adjust.dx ?? 0), dy: (last.dy ?? 0) + (adjust.dy ?? 0))
                return
            case .resize, .preset:
                pending[pending.count - 1] = adjust
                return
            }
        }
        pending.append(adjust)
    }

    mutating func take() -> [WindowAdjust] {
        defer { pending.removeAll() }
        return pending
    }
}

/// Giới hạn `window.adjust` mỗi giây (cửa sổ trượt 1 s). `preset` không bao giờ bị bỏ.
struct WindowAdjustRateLimiter {
    static let maxPerSecond = 60
    private var stamps: [Int64] = []

    mutating func allow(_ adjust: WindowAdjust, nowMs: Int64) -> Bool {
        stamps.removeAll { nowMs - $0 >= 1000 }
        if adjust.op == .preset { stamps.append(nowMs); return true }
        guard stamps.count < Self.maxPerSecond else { return false }
        stamps.append(nowMs)
        return true
    }
}
