import Testing
import XdeskWire
@testable import XdeskInput

@Suite struct TrackpadInterpreterTests {
    private func make(speed: Float = 1, natural: Bool = true, longPress: Bool = true) -> TrackpadInterpreter {
        var config = TrackpadConfig(surfaceWidth: 1000, surfaceHeight: 500)
        config.speed = speed
        config.naturalScroll = natural
        config.longPressRightClick = longPress
        return TrackpadInterpreter(config: config)
    }

    private func touch(_ id: Int, _ x: Float, _ y: Float, _ phase: TouchPhase, _ t: Int64) -> TouchSample {
        TouchSample(id: id, x: x, y: y, phase: phase, timeMs: t)
    }

    private func kinds(_ events: [InputEvent]) -> [InputKind] { events.map(\.kind) }

    @Test func tapClicksAtCursorNotAtFinger() {
        var t = make()
        #expect(t.handle(touch(1, 0.9, 0.9, .began, 0)).isEmpty)
        let out = t.handle(touch(1, 0.9, 0.9, .ended, 80))
        #expect(kinds(out) == [.move, .down, .up])
        #expect(out[1].x == 0.5 && out[1].y == 0.5 && out[1].button == InputButton.left && out[1].dx == 1)
    }

    @Test func jitterBelowSlopStaysATap() {
        var t = make()
        _ = t.handle(touch(1, 0.5, 0.5, .began, 0))
        #expect(t.handle(touch(1, 0.51, 0.5, .moved, 16)).isEmpty)
        #expect(kinds(t.handle(touch(1, 0.51, 0.5, .ended, 60))) == [.move, .down, .up])
        #expect(t.cursor.x == 0.5)
    }

    @Test func slowMoveIsRelativeWithLowGain() {
        var t = make()
        _ = t.handle(touch(1, 0.2, 0.5, .began, 0))
        // 0.1 chiều rộng trong 500 ms = 0.2 khung/s → gain ≈ 0.8 (làm mượt làm thấp hơn một chút).
        let out = t.handle(touch(1, 0.3, 0.5, .moved, 500))
        #expect(kinds(out) == [.move])
        #expect(out[0].x > 0.5 && out[0].x < 0.6)
        #expect(out[0].y == 0.5)
    }

    @Test func fastMoveTravelsFartherThanSlow() {
        var slow = make(), fast = make()
        _ = slow.handle(touch(1, 0.2, 0.5, .began, 0)); _ = fast.handle(touch(1, 0.2, 0.5, .began, 0))
        _ = slow.handle(touch(1, 0.3, 0.5, .moved, 1000))
        _ = fast.handle(touch(1, 0.3, 0.5, .moved, 50))
        #expect(fast.cursor.x - 0.5 > 2 * (slow.cursor.x - 0.5))
    }

    @Test func speedSettingScalesTravel() {
        var normal = make(speed: 1), quick = make(speed: 2)
        _ = normal.handle(touch(1, 0.2, 0.5, .began, 0)); _ = quick.handle(touch(1, 0.2, 0.5, .began, 0))
        _ = normal.handle(touch(1, 0.3, 0.5, .moved, 400)); _ = quick.handle(touch(1, 0.3, 0.5, .moved, 400))
        #expect(abs((quick.cursor.x - 0.5) - 2 * (normal.cursor.x - 0.5)) < 0.001)
    }

    @Test func cursorIsClampedToDisplay() {
        var t = make()
        _ = t.handle(touch(1, 0.1, 0.5, .began, 0))
        var time: Int64 = 0
        for x in stride(from: Float(0.2), through: 3.0, by: 0.2) {
            time += 20
            _ = t.handle(touch(1, x, -2, .moved, time))
        }
        #expect(t.cursor.x == 1 && t.cursor.y == 0)
        #expect(t.handle(touch(1, 3.2, -2.2, .moved, time + 20)).isEmpty, "đã chạm mép thì không gửi thêm move")
    }

    @Test func movingFingerDoesNotClickOnRelease() {
        var t = make()
        _ = t.handle(touch(1, 0.2, 0.5, .began, 0))
        _ = t.handle(touch(1, 0.4, 0.5, .moved, 100))
        #expect(t.handle(touch(1, 0.4, 0.5, .ended, 150)).isEmpty)
    }

    @Test func longPressIsRightClickAtCursorAndCanBeDisabled() {
        var t = make()
        _ = t.handle(touch(1, 0.2, 0.2, .began, 0))
        #expect(t.tick(nowMs: 499).isEmpty)
        let out = t.tick(nowMs: 500)
        #expect(kinds(out) == [.move, .down, .up] && out[1].button == InputButton.right && out[1].x == 0.5)
        #expect(t.handle(touch(1, 0.2, 0.2, .ended, 900)).isEmpty)

        var off = make(longPress: false)
        _ = off.handle(touch(1, 0.2, 0.2, .began, 0))
        #expect(off.tick(nowMs: 2000).isEmpty)
    }

    @Test func twoFingerTapIsRightClick() {
        var t = make()
        _ = t.handle(touch(1, 0.4, 0.5, .began, 0)); _ = t.handle(touch(2, 0.5, 0.5, .began, 10))
        #expect(t.handle(touch(2, 0.5, 0.5, .ended, 100)).isEmpty == false)
        #expect(t.handle(touch(1, 0.4, 0.5, .ended, 110)).isEmpty)
    }

    @Test func twoFingerTapTooSlowIsNotAClick() {
        var t = make()
        _ = t.handle(touch(1, 0.4, 0.5, .began, 0)); _ = t.handle(touch(2, 0.5, 0.5, .began, 10))
        #expect(t.handle(touch(2, 0.5, 0.5, .ended, 600)).isEmpty)
    }

    @Test func twoFingerDragScrollsNaturalAndReversed() {
        var natural = make(), reversed = make(natural: false)
        for (id, x) in [(1, Float(0.4)), (2, 0.6)] {
            _ = natural.handle(touch(id, x, 0.5, .began, Int64(id))); _ = reversed.handle(touch(id, x, 0.5, .began, Int64(id)))
        }
        // Ngón đầu dời trước (centroid đổi một nửa), ngón hai dời sau.
        let a = natural.handle(touch(1, 0.4, 0.6, .moved, 50)), b = reversed.handle(touch(1, 0.4, 0.6, .moved, 50))
        #expect(kinds(a) == [.scroll] && a[0].dy > 0)
        #expect(b[0].dy < 0 && abs(a[0].dy + b[0].dy) < 0.001)
        #expect(natural.cursor.x == 0.5, "cuộn không dời con trỏ")
    }

    @Test func tapThenTouchAndMoveDragsWithButtonDown() {
        var t = make()
        _ = t.handle(touch(1, 0.3, 0.3, .began, 0)); _ = t.handle(touch(1, 0.3, 0.3, .ended, 50))
        #expect(t.handle(touch(2, 0.6, 0.6, .began, 150)).isEmpty)
        let drag = t.handle(touch(2, 0.7, 0.6, .moved, 250))
        #expect(kinds(drag) == [.move, .down, .move])
        #expect(drag[1].button == InputButton.left)
        let more = t.handle(touch(2, 0.75, 0.6, .moved, 300))
        #expect(kinds(more) == [.move])
        let end = t.handle(touch(2, 0.75, 0.6, .ended, 400))
        #expect(kinds(end) == [.up])
    }

    @Test func tapThenTapIsDoubleClickAndLateSecondTapIsSingle() {
        var t = make()
        _ = t.handle(touch(1, 0.3, 0.3, .began, 0)); _ = t.handle(touch(1, 0.3, 0.3, .ended, 50))
        _ = t.handle(touch(2, 0.3, 0.3, .began, 150))
        #expect(t.handle(touch(2, 0.3, 0.3, .ended, 200))[1].dx == 2)
        _ = t.handle(touch(3, 0.3, 0.3, .began, 1000))
        #expect(t.handle(touch(3, 0.3, 0.3, .ended, 1050))[1].dx == 1)
    }

    @Test func secondFingerDuringDragReleasesButton() {
        var t = make()
        _ = t.handle(touch(1, 0.3, 0.3, .began, 0)); _ = t.handle(touch(1, 0.3, 0.3, .ended, 50))
        _ = t.handle(touch(2, 0.5, 0.5, .began, 100)); _ = t.handle(touch(2, 0.6, 0.5, .moved, 150))
        let out = t.handle(touch(3, 0.2, 0.2, .began, 200))
        #expect(kinds(out) == [.up])
    }

    @Test func cancelDuringDragReleasesButton() {
        var t = make()
        _ = t.handle(touch(1, 0.3, 0.3, .began, 0)); _ = t.handle(touch(1, 0.3, 0.3, .ended, 50))
        _ = t.handle(touch(2, 0.5, 0.5, .began, 100)); _ = t.handle(touch(2, 0.6, 0.5, .moved, 150))
        #expect(kinds(t.handle(touch(2, 0.6, 0.5, .cancelled, 200))) == [.up])
    }

    @Test func cursorSurvivesAcrossGestures() {
        var t = make()
        _ = t.handle(touch(1, 0.2, 0.5, .began, 0)); _ = t.handle(touch(1, 0.3, 0.5, .moved, 400)); _ = t.handle(touch(1, 0.3, 0.5, .ended, 450))
        let moved = t.cursor.x
        _ = t.handle(touch(2, 0.9, 0.1, .began, 2000))
        let out = t.handle(touch(2, 0.9, 0.1, .ended, 2050))
        #expect(out[1].x == moved)
    }
}
