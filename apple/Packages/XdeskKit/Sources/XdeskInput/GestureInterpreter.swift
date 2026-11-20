import XdeskWire

/// Chạm trực tiếp → con trỏ:
/// - chạm = click trái (liên tiếp = double/triple), chạm 2 ngón = click phải;
/// - vuốt 1 ngón = cuộn (con trỏ đặt ở chỗ bắt đầu vuốt để cuộn đúng cửa sổ), khoá theo trục chính;
/// - giữ 500 ms rồi kéo = giữ chuột trái và kéo thả; giữ rồi nhả không kéo = click phải;
/// - 2 ngón kéo = cuộn pixel; hất rồi nhả (1 hoặc 2 ngón) thì trang trôi tiếp và chậm dần.
/// Không phụ thuộc UIKit để test được.
/// Đầu ra có `seq` = 0; gửi qua `InputSequencer`/`ViewerSession.sendInput`.
public struct GestureInterpreter: Sendable {
    private enum Mode: Equatable {
        case idle
        case pending(id: Int)
        /// Một ngón vuốt: cuộn theo ngón tay.
        case swiping(id: Int)
        /// Đã giữ đủ lâu: kéo = kéo thả, nhả = click phải.
        case held(id: Int)
        case dragging(id: Int)
        case scrolling
        /// Đã dùng xong cử chỉ (long press, cuộn kết thúc); chờ nhả hết ngón.
        case consumed
    }

    private typealias Point = GesturePoint

    private var config: GestureConfig
    private var momentum = ScrollMomentum()
    private var mode = Mode.idle
    private var touches: [Int: Point] = [:]
    private var startPoint = Point(x: 0, y: 0)
    private var startMs: Int64 = 0
    private var lastTap: (point: Point, endMs: Int64, count: Int)?
    private var lastCentroid = Point(x: 0, y: 0)
    private var twoFingerTap: (startMs: Int64, start: Point)?
    /// Trục khoá khi vuốt một ngón: (1,0) ngang, (0,1) dọc, (1,1) tự do.
    private var swipeAxis = Point(x: 1, y: 1)

    public init(config: GestureConfig) { self.config = config }

    /// Đang giữ một ngón đủ lâu (sẵn sàng kéo thả / click phải): UI rung nhẹ khi trạng thái này bật lên.
    public var isHolding: Bool { if case .held = mode { true } else { false } }
    /// Còn việc cần `tick` (chờ nhấn giữ hoặc đang cuộn quán tính) dù không còn ngón nào trên màn hình.
    public var needsTick: Bool { momentum.isActive || !touches.isEmpty }

    /// Cập nhật tỉ lệ điểm host / điểm màn hình (đổi zoom, xoay máy) mà không mất trạng thái cử chỉ.
    public mutating func setHostPointsPerViewPoint(_ scale: Float) { config.hostPointsPerViewPoint = scale }

    public mutating func handle(_ sample: TouchSample) -> [InputEvent] {
        let point = Point(x: sample.x, y: sample.y)
        switch sample.phase {
        case .began: return began(sample.id, point, sample.timeMs)
        case .moved: return moved(sample.id, point, sample.timeMs)
        case .ended: return ended(sample.id, point, sample.timeMs)
        case .cancelled: return cancelled(sample.id, point)
        }
    }

    /// Gọi định kỳ (~50 ms): giữ đủ lâu thì con trỏ nhảy tới ngón tay, sẵn sàng kéo thả hoặc click phải khi nhả.
    public mutating func tick(nowMs: Int64) -> [InputEvent] {
        if let glide = momentum.step(nowMs: nowMs) {
            return glide.dx == 0 && glide.dy == 0 ? [] : [.scroll(dx: glide.dx, dy: glide.dy)]
        }
        guard case .pending(let id) = mode, nowMs - startMs >= config.longPressMs else { return [] }
        mode = .held(id: id)
        return [.move(x: startPoint.x, y: startPoint.y)]
    }

    // MARK: Pha

    private mutating func began(_ id: Int, _ point: Point, _ timeMs: Int64) -> [InputEvent] {
        touches[id] = point
        momentum.stop()
        switch mode {
        case .idle:
            mode = .pending(id: id)
            startPoint = point
            startMs = timeMs
            return []
        case .pending, .swiping, .held:
            return beginScroll(timeMs: timeMs)
        case .dragging(let dragId):
            mode = .scrolling
            twoFingerTap = nil
            lastCentroid = GestureMath.centroid(touches.values)
            return [releaseDrag(dragId)]
        case .scrolling, .consumed:
            return []
        }
    }

    private mutating func moved(_ id: Int, _ point: Point, _ timeMs: Int64) -> [InputEvent] {
        guard touches[id] != nil else { return [] }
        touches[id] = point
        switch mode {
        case .pending(let pendingId) where pendingId == id:
            guard GestureMath.distance(point, startPoint, in: config) > config.effectiveSlop else { return [] }
            mode = .swiping(id: id)
            swipeAxis = GestureMath.swipeAxis(dx: (point.x - startPoint.x) * config.surfaceWidth, dy: (point.y - startPoint.y) * config.surfaceHeight)
            lastCentroid = startPoint
            return [.move(x: startPoint.x, y: startPoint.y)] + scroll(to: point, timeMs: timeMs)
        case .swiping(let swipeId) where swipeId == id:
            return scroll(to: point, timeMs: timeMs)
        case .held(let heldId) where heldId == id:
            guard GestureMath.distance(point, startPoint, in: config) > config.effectiveSlop else { return [] }
            mode = .dragging(id: id)
            return [.button(down: true, x: startPoint.x, y: startPoint.y), .move(x: point.x, y: point.y)]
        case .dragging(let dragId) where dragId == id:
            return [.move(x: point.x, y: point.y)]
        case .scrolling:
            let now = GestureMath.centroid(touches.values)
            defer { lastCentroid = now }
            if let tap = twoFingerTap, GestureMath.distance(now, tap.start, in: config) > config.effectiveSlop { twoFingerTap = nil }
            let sign: Float = config.naturalScroll ? 1 : -1
            let dx = sign * (now.x - lastCentroid.x) * config.surfaceWidth, dy = sign * (now.y - lastCentroid.y) * config.surfaceHeight
            guard dx != 0 || dy != 0 else { return [] }
            momentum.track(dx: dx, dy: dy, timeMs: timeMs)
            return [.scroll(dx: dx, dy: dy)]
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
            return [.move(x: point.x, y: point.y)] + GestureMath.click(InputButton.left, at: point, count: count)
        case .held(let heldId) where heldId == id:
            let button = config.longPressRightClick ? InputButton.right : InputButton.left
            return GestureMath.click(button, at: startPoint, count: 1)
        case .dragging(let dragId) where dragId == id:
            return [.button(down: false, x: point.x, y: point.y)]
        case .swiping(let swipeId) where swipeId == id:
            momentum.release(timeMs: timeMs)
            return []
        case .scrolling:
            guard let tap = twoFingerTap, touches.count == 2, timeMs - tap.startMs <= config.twoFingerTapMs else {
                momentum.release(timeMs: timeMs)
                return []
            }
            twoFingerTap = nil
            let center = GestureMath.centroid(touches.values)
            return [.move(x: center.x, y: center.y)] + GestureMath.click(InputButton.right, at: center, count: 1)
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
        lastCentroid = GestureMath.centroid(touches.values)
        twoFingerTap = touches.count == 2 ? (timeMs, lastCentroid) : nil
        return []
    }

    /// Một ngón vuốt: nội dung đi theo ngón tay (cuộn tự nhiên), chỉ theo trục đã khoá.
    private mutating func scroll(to point: Point, timeMs: Int64) -> [InputEvent] {
        defer { lastCentroid = point }
        let sign: Float = config.naturalScroll ? 1 : -1
        let dx = sign * (point.x - lastCentroid.x) * config.surfaceWidth * swipeAxis.x
        let dy = sign * (point.y - lastCentroid.y) * config.surfaceHeight * swipeAxis.y
        guard dx != 0 || dy != 0 else { return [] }
        momentum.track(dx: dx, dy: dy, timeMs: timeMs)
        return [.scroll(dx: dx, dy: dy)]
    }

    private func releaseDrag(_ id: Int) -> InputEvent {
        let p = touches[id] ?? startPoint
        return .button(down: false, x: p.x, y: p.y)
    }

    private func nextTapCount(at p: Point, timeMs: Int64) -> Int {
        guard let last = lastTap, timeMs - last.endMs <= config.doubleTapMs, GestureMath.distance(p, last.point, in: config) <= config.effectiveSlop * 2 else { return 1 }
        return last.count + 1
    }
}
