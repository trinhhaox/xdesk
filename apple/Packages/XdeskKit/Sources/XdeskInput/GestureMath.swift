import XdeskWire

/// Điểm chuẩn hoá 0…1 trên khung video.
struct GesturePoint: Sendable {
    var x: Float
    var y: Float
}

/// Phép tính thuần cho bộ diễn giải cử chỉ (không giữ trạng thái).
enum GestureMath {
    static func click(_ button: UInt8, at p: GesturePoint, count: Int) -> [InputEvent] {
        [.button(down: true, button: button, x: p.x, y: p.y, clickCount: count), .button(down: false, button: button, x: p.x, y: p.y, clickCount: count)]
    }

    /// Hướng vuốt rõ ràng (gấp đôi trục kia) thì khoá theo trục đó: cuộn dọc không lệch ngang và ngược lại.
    /// (1,0) ngang, (0,1) dọc, (1,1) tự do.
    static func swipeAxis(dx: Float, dy: Float) -> GesturePoint {
        if abs(dy) >= 2 * abs(dx) { return GesturePoint(x: 0, y: 1) }
        if abs(dx) >= 2 * abs(dy) { return GesturePoint(x: 1, y: 0) }
        return GesturePoint(x: 1, y: 1)
    }

    static func centroid(_ points: Dictionary<Int, GesturePoint>.Values) -> GesturePoint {
        let n = Float(max(1, points.count))
        return GesturePoint(x: points.reduce(0) { $0 + $1.x } / n, y: points.reduce(0) { $0 + $1.y } / n)
    }

    /// Khoảng cách theo điểm host.
    static func distance(_ a: GesturePoint, _ b: GesturePoint, in config: GestureConfig) -> Float {
        let dx = (a.x - b.x) * config.surfaceWidth, dy = (a.y - b.y) * config.surfaceHeight
        return (dx * dx + dy * dy).squareRoot()
    }
}
