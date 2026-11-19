import XdeskWire

public struct TrackpadConfig: Sendable, Equatable {
    /// Kích thước màn hình host theo điểm; đổi delta chuẩn hoá → pixel cuộn.
    public var surfaceWidth: Float
    public var surfaceHeight: Float
    public var speed: Float = 1
    public var naturalScroll = true
    public var longPressRightClick = true
    public var longPressMs: Int64 = 500
    public var doubleTapMs: Int64 = 300
    public var twoFingerTapMs: Int64 = 300
    /// Ngón di chuyển ít hơn mức này (tỉ lệ chiều rộng khung video) vẫn là chạm; 0.02 ≈ 8 pt trên iPhone 390 pt.
    public var tapSlop: Float = 0.02

    public init(surfaceWidth: Float, surfaceHeight: Float) {
        self.surfaceWidth = surfaceWidth
        self.surfaceHeight = surfaceHeight
    }
}

/// Chạm kiểu trackpad: 1 ngón trượt = di chuyển con trỏ tương đối (có gia tốc), chạm = click tại con trỏ,
/// 2 ngón chạm = click phải, 2 ngón trượt = cuộn, chạm-rồi-chạm-giữ-và-trượt = kéo. Wire chỉ có toạ độ tuyệt đối
/// nên viewer tự giữ vị trí con trỏ (0…1 trên màn hình host, luôn bị ép vào khung). Mẫu chạm là toạ độ chuẩn hoá của khung video
/// (có thể ngoài 0…1 khi ngón trượt qua dải đen). Không phụ thuộc UIKit để test được.
public struct TrackpadInterpreter: Sendable {
    private enum Mode: Equatable {
        case idle
        /// `secondTap`: ngón đặt xuống ngay sau một cú chạm; trượt sẽ thành kéo, nhả sẽ thành double click.
        case pending(id: Int, secondTap: Bool)
        case moving(id: Int)
        case dragging(id: Int)
        case scrolling
        case consumed
    }

    private struct Point { var x: Float, y: Float }

    private let config: TrackpadConfig
    private var mode = Mode.idle
    private var touches: [Int: Point] = [:]
    private var startPoint = Point(x: 0, y: 0)
    private var startMs: Int64 = 0
    private var previous = Point(x: 0, y: 0)
    private var previousMs: Int64 = 0
    private var velocity: Float = 0
    private var lastTap: (endMs: Int64, count: Int)?
    private var lastCentroid = Point(x: 0, y: 0)
    private var twoFingerTap: (startMs: Int64, start: Point)?
    private var position: Point

    /// Vị trí con trỏ (0…1 trên màn hình host).
    public var cursor: (x: Float, y: Float) { (position.x, position.y) }

    public init(config: TrackpadConfig, cursor: (x: Float, y: Float) = (0.5, 0.5)) {
        self.config = config
        position = Point(x: min(1, max(0, cursor.x)), y: min(1, max(0, cursor.y)))
    }

    public mutating func handle(_ sample: TouchSample) -> [InputEvent] {
        let point = Point(x: sample.x, y: sample.y)
        switch sample.phase {
        case .began: return began(sample.id, point, sample.timeMs)
        case .moved: return moved(sample.id, point, sample.timeMs)
        case .ended: return ended(sample.id, timeMs: sample.timeMs)
        case .cancelled: return cancelled(sample.id)
        }
    }

    /// Gọi định kỳ (~50 ms) để phát click phải khi giữ đủ lâu.
    public mutating func tick(nowMs: Int64) -> [InputEvent] {
        guard config.longPressRightClick, case .pending(_, false) = mode, nowMs - startMs >= config.longPressMs else { return [] }
        mode = .consumed
        lastTap = nil
        return clickAtCursor(InputButton.right, count: 1)
    }

    private mutating func began(_ id: Int, _ point: Point, _ timeMs: Int64) -> [InputEvent] {
        touches[id] = point
        switch mode {
        case .idle:
            let second = lastTap.map { timeMs - $0.endMs <= config.doubleTapMs } ?? false
            mode = .pending(id: id, secondTap: second)
            startPoint = point; previous = point; previousMs = timeMs; startMs = timeMs; velocity = 0
            return []
        case .pending, .moving:
            if case .pending = mode { startScrolling(asTap: touches.count == 2, timeMs: timeMs) } else { startScrolling(asTap: false, timeMs: timeMs) }
            return []
        case .dragging:
            startScrolling(asTap: false, timeMs: timeMs)
            return [.button(down: false, x: position.x, y: position.y)]
        case .scrolling, .consumed:
            return []
        }
    }

    private mutating func moved(_ id: Int, _ point: Point, _ timeMs: Int64) -> [InputEvent] {
        guard touches[id] != nil else { return [] }
        touches[id] = point
        switch mode {
        case .pending(let pendingId, let second) where pendingId == id:
            guard distance(point, startPoint) > config.tapSlop else { return [] }
            lastTap = nil
            mode = second ? .dragging(id: id) : .moving(id: id)
            let press: [InputEvent] = second ? [.move(x: position.x, y: position.y), .button(down: true, x: position.x, y: position.y)] : []
            return press + moveCursor(to: point, timeMs: timeMs)
        case .moving(let movingId) where movingId == id, .dragging(let movingId) where movingId == id:
            return moveCursor(to: point, timeMs: timeMs)
        case .scrolling:
            return scrolled()
        default:
            return []
        }
    }

    private mutating func ended(_ id: Int, timeMs: Int64) -> [InputEvent] {
        guard touches[id] != nil else { return [] }
        let events: [InputEvent]
        switch mode {
        case .pending(let pendingId, let second) where pendingId == id:
            let count = second ? (lastTap?.count ?? 0) + 1 : 1
            lastTap = (timeMs, count)
            events = clickAtCursor(InputButton.left, count: count)
        case .dragging(let dragId) where dragId == id:
            events = [.button(down: false, x: position.x, y: position.y)]
        case .scrolling:
            if let tap = twoFingerTap, touches.count == 2, timeMs - tap.startMs <= config.twoFingerTapMs {
                twoFingerTap = nil
                events = clickAtCursor(InputButton.right, count: 1)
            } else { events = [] }
        default:
            events = []
        }
        touches[id] = nil
        mode = touches.isEmpty ? .idle : .consumed
        return events
    }

    private mutating func cancelled(_ id: Int) -> [InputEvent] {
        guard touches[id] != nil else { return [] }
        var events: [InputEvent] = []
        if case .dragging(let dragId) = mode, dragId == id { events = [.button(down: false, x: position.x, y: position.y)] }
        touches[id] = nil
        mode = touches.isEmpty ? .idle : .consumed
        return events
    }

    private mutating func startScrolling(asTap: Bool, timeMs: Int64) {
        mode = .scrolling
        lastCentroid = centroid()
        twoFingerTap = asTap ? (timeMs, lastCentroid) : nil
    }

    private mutating func scrolled() -> [InputEvent] {
        let now = centroid()
        defer { lastCentroid = now }
        if let tap = twoFingerTap, distance(now, tap.start) > config.tapSlop { twoFingerTap = nil }
        let sign: Float = config.naturalScroll ? 1 : -1
        let dx = sign * (now.x - lastCentroid.x) * config.surfaceWidth, dy = sign * (now.y - lastCentroid.y) * config.surfaceHeight
        return dx == 0 && dy == 0 ? [] : [.scroll(dx: dx, dy: dy)]
    }

    /// Dời con trỏ theo độ dời của ngón nhân gia tốc theo vận tốc (làm mượt 50/50 để bớt nhiễu mẫu).
    private mutating func moveCursor(to point: Point, timeMs: Int64) -> [InputEvent] {
        let dx = point.x - previous.x, dy = point.y - previous.y
        let dt = Float(max(4, timeMs - previousMs)) / 1000
        let instant = distance(point, previous) / dt
        velocity = (velocity + instant) / 2
        previous = point
        previousMs = timeMs
        let gain = PointerAcceleration.gain(velocity: velocity, speed: config.speed)
        let next = Point(x: min(1, max(0, position.x + dx * gain)), y: min(1, max(0, position.y + dy * gain)))
        guard next.x != position.x || next.y != position.y else { return [] }
        position = next
        return [.move(x: next.x, y: next.y)]
    }

    private func clickAtCursor(_ button: UInt8, count: Int) -> [InputEvent] {
        [.move(x: position.x, y: position.y),
         .button(down: true, button: button, x: position.x, y: position.y, clickCount: count),
         .button(down: false, button: button, x: position.x, y: position.y, clickCount: count)]
    }

    private func centroid() -> Point {
        let all = touches.values
        let n = Float(max(1, all.count))
        return Point(x: all.reduce(0) { $0 + $1.x } / n, y: all.reduce(0) { $0 + $1.y } / n)
    }

    /// Khoảng cách theo tỉ lệ chiều rộng màn hình host (chiều dọc đổi theo khung hình).
    private func distance(_ a: Point, _ b: Point) -> Float {
        let dx = a.x - b.x, dy = (a.y - b.y) * config.surfaceHeight / max(1, config.surfaceWidth)
        return (dx * dx + dy * dy).squareRoot()
    }
}
