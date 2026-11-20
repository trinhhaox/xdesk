import Testing
import XdeskWire
@testable import XdeskInput

@Suite struct GestureInterpreterTests {
    private func makeInterpreter() -> GestureInterpreter {
        GestureInterpreter(config: GestureConfig(surfaceWidth: 1000, surfaceHeight: 500))
    }

    private func touch(_ id: Int, _ x: Float, _ y: Float, _ phase: TouchPhase, _ t: Int64) -> TouchSample {
        TouchSample(id: id, x: x, y: y, phase: phase, timeMs: t)
    }

    private func kinds(_ events: [InputEvent]) -> [InputKind] { events.map(\.kind) }

    @Test func tapIsLeftClick() {
        var g = makeInterpreter()
        #expect(g.handle(touch(1, 0.5, 0.5, .began, 0)).isEmpty)
        let out = g.handle(touch(1, 0.5, 0.5, .ended, 80))
        #expect(kinds(out) == [.move, .down, .up])
        #expect(out[1].button == InputButton.left && out[1].x == 0.5 && out[1].dx == 1)
        #expect(out[2].button == InputButton.left)
    }

    @Test func quickSecondTapIsDoubleClick() {
        var g = makeInterpreter()
        _ = g.handle(touch(1, 0.2, 0.2, .began, 0)); _ = g.handle(touch(1, 0.2, 0.2, .ended, 50))
        _ = g.handle(touch(2, 0.2, 0.2, .began, 150))
        let out = g.handle(touch(2, 0.2, 0.2, .ended, 200))
        #expect(out[1].dx == 2)
        _ = g.handle(touch(3, 0.2, 0.2, .began, 2000))
        #expect(g.handle(touch(3, 0.2, 0.2, .ended, 2050))[1].dx == 1)
    }

    @Test func longPressThenReleaseIsRightClick() {
        var g = makeInterpreter()
        _ = g.handle(touch(1, 0.4, 0.6, .began, 0))
        #expect(g.tick(nowMs: 499).isEmpty)
        let held = g.tick(nowMs: 500)
        #expect(kinds(held) == [.move]) // con trỏ tới ngón tay, chưa click
        #expect(held[0].x == 0.4 && held[0].y == 0.6)
        #expect(g.tick(nowMs: 900).isEmpty)
        let out = g.handle(touch(1, 0.4, 0.6, .ended, 1000))
        #expect(kinds(out) == [.down, .up])
        #expect(out[0].button == InputButton.right && out[0].x == 0.4 && out[0].y == 0.6)
    }

    @Test func longPressWithRightClickOffReleasesAsLeftClick() {
        var config = GestureConfig(surfaceWidth: 1000, surfaceHeight: 500)
        config.longPressRightClick = false
        var g = GestureInterpreter(config: config)
        _ = g.handle(touch(1, 0.4, 0.6, .began, 0))
        _ = g.tick(nowMs: 600)
        let out = g.handle(touch(1, 0.4, 0.6, .ended, 700))
        #expect(kinds(out) == [.down, .up] && out[0].button == InputButton.left)
    }

    @Test func smallJitterStillTaps() {
        var g = makeInterpreter()
        _ = g.handle(touch(1, 0.5, 0.5, .began, 0))
        #expect(g.handle(touch(1, 0.504, 0.5, .moved, 20)).isEmpty) // 4 điểm < slop 8
        #expect(kinds(g.handle(touch(1, 0.504, 0.5, .ended, 60))) == [.move, .down, .up])
    }

    @Test func oneFingerSwipeUpAndDownScrolls() {
        var g = makeInterpreter()
        _ = g.handle(touch(1, 0.5, 0.5, .began, 0))
        let start = g.handle(touch(1, 0.5, 0.4, .moved, 30))
        #expect(kinds(start) == [.move, .scroll]) // con trỏ về chỗ bắt đầu vuốt rồi cuộn
        #expect(start[0].x == 0.5 && start[0].y == 0.5)
        #expect(start[1].dx == 0 && abs(start[1].dy - -50) < 0.001) // 0.1 × 500, nội dung đi theo ngón
        let down = g.handle(touch(1, 0.5, 0.6, .moved, 60))
        #expect(kinds(down) == [.scroll] && abs(down[0].dy - 100) < 0.001)
        #expect(g.handle(touch(1, 0.5, 0.6, .ended, 400)).isEmpty) // ngón đã dừng rồi mới nhả: không trôi
        #expect(g.tick(nowMs: 2000).isEmpty)
    }

    @Test func verticalSwipeIgnoresSidewaysWobble() {
        var g = makeInterpreter()
        _ = g.handle(touch(1, 0.5, 0.5, .began, 0))
        _ = g.handle(touch(1, 0.5, 0.4, .moved, 30))
        let out = g.handle(touch(1, 0.52, 0.3, .moved, 60))
        #expect(out[0].dx == 0 && abs(out[0].dy - -50) < 0.001)
    }

    @Test func naturalScrollOffReversesSwipe() {
        var config = GestureConfig(surfaceWidth: 1000, surfaceHeight: 500)
        config.naturalScroll = false
        var g = GestureInterpreter(config: config)
        _ = g.handle(touch(1, 0.5, 0.5, .began, 0))
        let out = g.handle(touch(1, 0.5, 0.4, .moved, 30))
        #expect(abs(out[1].dy - 50) < 0.001)
    }

    @Test func swipeDoesNotTurnIntoLongPress() {
        var g = makeInterpreter()
        _ = g.handle(touch(1, 0.5, 0.5, .began, 0))
        _ = g.handle(touch(1, 0.5, 0.4, .moved, 30))
        #expect(g.tick(nowMs: 800).isEmpty)
        #expect(g.handle(touch(1, 0.5, 0.4, .ended, 900)).isEmpty)
    }

    @Test func holdThenDragHoldsLeftButtonThenReleases() {
        var g = makeInterpreter()
        _ = g.handle(touch(1, 0.1, 0.1, .began, 0))
        #expect(kinds(g.tick(nowMs: 500)) == [.move])
        let start = g.handle(touch(1, 0.2, 0.1, .moved, 530))
        #expect(kinds(start) == [.down, .move])
        #expect(start[0].x == 0.1 && start[1].x == 0.2)
        #expect(kinds(g.handle(touch(1, 0.3, 0.1, .moved, 560))) == [.move])
        let end = g.handle(touch(1, 0.3, 0.1, .ended, 590))
        #expect(kinds(end) == [.up])
        #expect(end[0].button == InputButton.left && end[0].x == 0.3)
        #expect(g.tick(nowMs: 2000).isEmpty)
    }

    @Test func twoFingerPanScrollsInPixels() {
        var g = makeInterpreter()
        _ = g.handle(touch(1, 0.4, 0.4, .began, 0))
        _ = g.handle(touch(2, 0.6, 0.4, .began, 10))
        let first = g.handle(touch(1, 0.4, 0.5, .moved, 40))
        #expect(kinds(first) == [.scroll]) // trọng tâm dịch 0.05 × 500 = 25
        #expect(first[0].dx == 0 && abs(first[0].dy - 25) < 0.001)
        let second = g.handle(touch(2, 0.6, 0.5, .moved, 50))
        #expect(abs(second[0].dy - 25) < 0.001)
        #expect(g.handle(touch(1, 0.4, 0.5, .ended, 80)).isEmpty)
        #expect(g.handle(touch(2, 0.6, 0.5, .ended, 90)).isEmpty)
        // Sau khi nhả hết, ngón mới là cử chỉ mới.
        _ = g.handle(touch(3, 0.5, 0.5, .began, 500))
        #expect(kinds(g.handle(touch(3, 0.5, 0.5, .ended, 540))) == [.move, .down, .up])
    }

    @Test func secondFingerDuringDragReleasesButton() {
        var g = makeInterpreter()
        _ = g.handle(touch(1, 0.1, 0.1, .began, 0))
        _ = g.tick(nowMs: 500)
        _ = g.handle(touch(1, 0.3, 0.1, .moved, 530))
        let out = g.handle(touch(2, 0.8, 0.8, .began, 60))
        #expect(kinds(out) == [.up])
    }

    @Test func twoFingerTapIsRightClickAtCentroid() {
        var g = makeInterpreter()
        _ = g.handle(touch(1, 0.4, 0.5, .began, 0))
        _ = g.handle(touch(2, 0.6, 0.5, .began, 10))
        let out = g.handle(touch(1, 0.4, 0.5, .ended, 120))
        #expect(kinds(out) == [.move, .down, .up])
        #expect(out[1].button == InputButton.right && out[1].x == 0.5 && out[1].y == 0.5)
        #expect(g.handle(touch(2, 0.6, 0.5, .ended, 130)).isEmpty)
    }

    @Test func slowTwoFingerHoldIsNotRightClick() {
        var g = makeInterpreter()
        _ = g.handle(touch(1, 0.5, 0.5, .began, 0))
        _ = g.handle(touch(2, 0.6, 0.5, .began, 10))
        #expect(g.handle(touch(1, 0.5, 0.5, .ended, 400)).isEmpty)
        #expect(g.handle(touch(2, 0.6, 0.5, .ended, 410)).isEmpty)
    }

    @Test func twoFingerScrollIsNotRightClick() {
        var g = makeInterpreter()
        _ = g.handle(touch(1, 0.4, 0.5, .began, 0))
        _ = g.handle(touch(2, 0.6, 0.5, .began, 10))
        _ = g.handle(touch(1, 0.4, 0.6, .moved, 40))
        _ = g.handle(touch(2, 0.6, 0.6, .moved, 40))
        #expect(g.handle(touch(1, 0.4, 0.6, .ended, 100)).isEmpty)
    }

    @Test func threeFingerTouchIsNotRightClick() {
        var g = makeInterpreter()
        _ = g.handle(touch(1, 0.4, 0.5, .began, 0))
        _ = g.handle(touch(2, 0.5, 0.5, .began, 10))
        _ = g.handle(touch(3, 0.6, 0.5, .began, 20))
        #expect(g.handle(touch(1, 0.4, 0.5, .ended, 80)).isEmpty)
    }

    @Test func cancelDuringDragReleasesButton() {
        var g = makeInterpreter()
        _ = g.handle(touch(1, 0.1, 0.1, .began, 0))
        _ = g.tick(nowMs: 500)
        _ = g.handle(touch(1, 0.3, 0.1, .moved, 530))
        #expect(kinds(g.handle(touch(1, 0.3, 0.1, .cancelled, 60))) == [.up])
    }
}
