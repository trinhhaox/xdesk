import XdeskWire

public enum TouchPhase: Sendable, Equatable {
    case began, moved, ended, cancelled
}

/// Một mẫu chạm trừu tượng: toạ độ chuẩn hoá 0…1 trên khung video, thời gian đơn điệu (ms).
public struct TouchSample: Sendable, Equatable {
    public var id: Int
    public var x: Float
    public var y: Float
    public var phase: TouchPhase
    public var timeMs: Int64

    public init(id: Int, x: Float, y: Float, phase: TouchPhase, timeMs: Int64) {
        self.id = id; self.x = x; self.y = y; self.phase = phase; self.timeMs = timeMs
    }
}

public struct GestureConfig: Sendable, Equatable {
    /// Kích thước màn hình host theo điểm; đổi delta chuẩn hoá → pixel và đo ngưỡng di chuyển.
    public var surfaceWidth: Float
    public var surfaceHeight: Float
    public var longPressMs: Int64 = 500
    public var doubleTapMs: Int64 = 300
    /// Hai ngón chạm rồi nhả trong khoảng này (không trượt) = click phải.
    public var twoFingerTapMs: Int64 = 300
    /// Di chuyển dưới ngưỡng này (điểm) vẫn tính là chạm.
    public var slop: Float = 8

    public init(surfaceWidth: Float, surfaceHeight: Float) {
        self.surfaceWidth = surfaceWidth
        self.surfaceHeight = surfaceHeight
    }
}

/// Chạm → con trỏ: chạm = click trái (liên tiếp = double/triple), giữ 500 ms hoặc chạm 2 ngón = click phải,
/// 1 ngón kéo = giữ chuột trái và kéo, 2 ngón kéo = cuộn pixel. Không phụ thuộc UIKit để test được.
/// Đầu ra có `seq` = 0; gửi qua `InputSequencer`/`ViewerSession.sendInput`.
public struct GestureInterpreter: Sendable {
    private enum Mode: Equatable {
        case idle
        case pending(id: Int)
        case dragging(id: Int)
        case scrolling
        /// Đã dùng xong cử chỉ (long press, cuộn kết thúc); chờ nhả hết ngón.
        case consumed
    }

    private struct Point { var x: Float, y: Float }

    private let config: GestureConfig
    private var mode = Mode.idle
    private var touches: [Int: Point] = [:]
    private var startPoint = Point(x: 0, y: 0)
    private var startMs: Int64 = 0
    private var lastTap: (point: Point, endMs: Int64, count: Int)?
    private var lastCentroid = Point(x: 0, y: 0)
    private var twoFingerTap: (startMs: Int64, start: Point)?

    public init(config: GestureConfig) { self.config = config }

    public mutating func handle(_ sample: TouchSample) -> [InputEvent] {
        let point = Point(x: sample.x, y: sample.y)
        switch sample.phase {
        case .began: return began(sample.id, point, sample.timeMs)
        case .moved: return moved(sample.id, point)
        case .ended: return ended(sample.id, point, sample.timeMs)
        case .cancelled: return cancelled(sample.id, point)
        }
    }

    /// Gọi định kỳ (~50 ms) để phát click phải khi giữ đủ lâu.
    public mutating func tick(nowMs: Int64) -> [InputEvent] {
        guard case .pending = mode, nowMs - startMs >= config.longPressMs else { return [] }
        mode = .consumed
        return [.move(x: startPoint.x, y: startPoint.y)] + click(InputButton.right, at: startPoint, count: 1)
    }

    // MARK: Pha

    private mutating func began(_ id: Int, _ point: Point, _ timeMs: Int64) -> [InputEvent] {
        touches[id] = point
        switch mode {
        case .idle:
            mode = .pending(id: id)
            startPoint = point
            startMs = timeMs
            return []
        case .pending:
            return beginScroll(timeMs: timeMs)
        case .dragging(let dragId):
            mode = .scrolling
            twoFingerTap = nil
            lastCentroid = centroid()
            return [releaseDrag(dragId)]
        case .scrolling, .consumed:
            return []
        }
    }

    private mutating func moved(_ id: Int, _ point: Point) -> [InputEvent] {
        guard touches[id] != nil else { return [] }
        touches[id] = point
        switch mode {
        case .pending(let pendingId) where pendingId == id:
            guard distance(point, startPoint) > config.slop else { return [] }
            mode = .dragging(id: id)
            return [.move(x: startPoint.x, y: startPoint.y), .button(down: true, x: startPoint.x, y: startPoint.y), .move(x: point.x, y: point.y)]
        case .dragging(let dragId) where dragId == id:
            return [.move(x: point.x, y: point.y)]
        case .scrolling:
            let now = centroid()
            defer { lastCentroid = now }
            if let tap = twoFingerTap, distance(now, tap.start) > config.slop { twoFingerTap = nil }
            let dx = (now.x - lastCentroid.x) * config.surfaceWidth, dy = (now.y - lastCentroid.y) * config.surfaceHeight
            return dx == 0 && dy == 0 ? [] : [.scroll(dx: dx, dy: dy)]
        default:
            return []
        }
    }

    private mutating func ended(_ id: Int, _ point: Point, _ timeMs: Int64) -> [InputEvent] {
        guard touches[id] != nil else { return [] }
        touches[id] = point
        defer {
            touches[id] = nil
            if touches.isEmpty { mode = .idle } else if mode != .consumed { mode = .consumed }
        }
        switch mode {
        case .pending(let pendingId) where pendingId == id:
            let count = nextTapCount(at: point, timeMs: timeMs)
            lastTap = (point, timeMs, count)
            return [.move(x: point.x, y: point.y)] + click(InputButton.left, at: point, count: count)
        case .dragging(let dragId) where dragId == id:
            return [.button(down: false, x: point.x, y: point.y)]
        case .scrolling:
            guard let tap = twoFingerTap, touches.count == 2, timeMs - tap.startMs <= config.twoFingerTapMs else { return [] }
            twoFingerTap = nil
            let center = centroid()
            return [.move(x: center.x, y: center.y)] + click(InputButton.right, at: center, count: 1)
        default:
            return []
        }
    }

    private mutating func cancelled(_ id: Int, _ point: Point) -> [InputEvent] {
        guard touches[id] != nil else { return [] }
        let events: [InputEvent]
        if case .dragging(let dragId) = mode, dragId == id { events = [releaseDrag(id)] } else { events = [] }
        touches[id] = nil
        if touches.isEmpty { mode = .idle } else { mode = .consumed }
        return events
    }

    // MARK: Hỗ trợ

    private mutating func beginScroll(timeMs: Int64) -> [InputEvent] {
        mode = .scrolling
        lastCentroid = centroid()
        twoFingerTap = touches.count == 2 ? (timeMs, lastCentroid) : nil
        return []
    }

    private func releaseDrag(_ id: Int) -> InputEvent {
        let p = touches[id] ?? startPoint
        return .button(down: false, x: p.x, y: p.y)
    }

    private func click(_ button: UInt8, at p: Point, count: Int) -> [InputEvent] {
        [.button(down: true, button: button, x: p.x, y: p.y, clickCount: count), .button(down: false, button: button, x: p.x, y: p.y, clickCount: count)]
    }

    private func nextTapCount(at p: Point, timeMs: Int64) -> Int {
        guard let last = lastTap, timeMs - last.endMs <= config.doubleTapMs, distance(p, last.point) <= config.slop * 2 else { return 1 }
        return last.count + 1
    }

    private func centroid() -> Point {
        let all = touches.values
        let n = Float(max(1, all.count))
        return Point(x: all.reduce(0) { $0 + $1.x } / n, y: all.reduce(0) { $0 + $1.y } / n)
    }

    private func distance(_ a: Point, _ b: Point) -> Float {
        let dx = (a.x - b.x) * config.surfaceWidth, dy = (a.y - b.y) * config.surfaceHeight
        return (dx * dx + dy * dy).squareRoot()
    }
}
