import Testing
import XdeskWire
@testable import XdeskInput

/// Cuộn quán tính, ngưỡng chạm theo điểm màn hình điện thoại và trạng thái nhấn giữ (cho rung).
@Suite struct GestureMomentumAndSlopTests {
    private func touch(_ id: Int, _ x: Float, _ y: Float, _ phase: TouchPhase, _ t: Int64) -> TouchSample {
        TouchSample(id: id, x: x, y: y, phase: phase, timeMs: t)
    }

    private func flick(_ g: inout GestureInterpreter, releaseAt: Int64 = 50) {
        _ = g.handle(touch(1, 0.5, 0.8, .began, 0))
        for (i, y) in [Float(0.7), 0.6, 0.5, 0.4].enumerated() { _ = g.handle(touch(1, 0.5, y, .moved, Int64(10 * (i + 1)))) }
        _ = g.handle(touch(1, 0.5, 0.4, .ended, releaseAt))
    }

    @Test func flickKeepsScrollingThenSlowsDownAndStops() {
        var g = GestureInterpreter(config: GestureConfig(surfaceWidth: 1000, surfaceHeight: 500))
        flick(&g)
        #expect(g.needsTick)
        let first = g.tick(nowMs: 100)
        let second = g.tick(nowMs: 150)
        #expect(first.first?.kind == .scroll && (first.first?.dy ?? 0) < 0, "trôi tiếp cùng chiều vuốt lên")
        #expect(abs(second.first?.dy ?? 0) < abs(first.first?.dy ?? 0), "chậm dần")
        var t: Int64 = 200
        while g.needsTick, t < 10_000 { _ = g.tick(nowMs: t); t += 50 }
        #expect(!g.needsTick && t < 10_000, "dừng hẳn sau vài giây")
        #expect(g.tick(nowMs: t + 50).isEmpty)
    }

    @Test func fingerThatStopsBeforeReleaseDoesNotGlide() {
        var g = GestureInterpreter(config: GestureConfig(surfaceWidth: 1000, surfaceHeight: 500))
        flick(&g, releaseAt: 400)
        #expect(!g.needsTick)
        #expect(g.tick(nowMs: 450).isEmpty)
    }

    @Test func touchingAgainStopsTheGlide() {
        var g = GestureInterpreter(config: GestureConfig(surfaceWidth: 1000, surfaceHeight: 500))
        flick(&g)
        _ = g.handle(touch(2, 0.5, 0.5, .began, 60))
        #expect(g.tick(nowMs: 100).isEmpty)
        #expect(kinds(g.handle(touch(2, 0.5, 0.5, .ended, 120))) == [.move, .down, .up], "chạm để dừng vẫn là một cú click")
    }

    @Test func slopFollowsTheFingerNotTheHostScreen() {
        // Mac 2000 điểm hiện trên 400 điểm điện thoại: 1 điểm màn hình = 5 điểm host → ngưỡng 50 điểm host.
        var config = GestureConfig(surfaceWidth: 2000, surfaceHeight: 1000)
        config.hostPointsPerViewPoint = 5
        var g = GestureInterpreter(config: config)
        _ = g.handle(touch(1, 0.5, 0.5, .began, 0))
        #expect(g.handle(touch(1, 0.5, 0.53, .moved, 20)).isEmpty, "30 điểm host = 6 điểm dưới ngón: vẫn là chạm")
        #expect(kinds(g.handle(touch(1, 0.5, 0.53, .ended, 60))) == [.move, .down, .up])
    }

    @Test func zoomChangeUpdatesSlopWithoutLosingState() {
        var g = GestureInterpreter(config: GestureConfig(surfaceWidth: 2000, surfaceHeight: 1000))
        _ = g.handle(touch(1, 0.5, 0.5, .began, 0))
        g.setHostPointsPerViewPoint(5)
        #expect(g.handle(touch(1, 0.5, 0.53, .moved, 20)).isEmpty)
        g.setHostPointsPerViewPoint(1)
        #expect(kinds(g.handle(touch(1, 0.5, 0.53, .moved, 30))) == [.move, .scroll])
    }

    @Test func isHoldingTurnsOnAfterLongPressAndOffWhenDragging() {
        var g = GestureInterpreter(config: GestureConfig(surfaceWidth: 1000, surfaceHeight: 500))
        _ = g.handle(touch(1, 0.2, 0.2, .began, 0))
        #expect(!g.isHolding)
        _ = g.tick(nowMs: 500)
        #expect(g.isHolding)
        _ = g.handle(touch(1, 0.4, 0.2, .moved, 520))
        #expect(!g.isHolding)
    }

    private func kinds(_ events: [InputEvent]) -> [InputKind] { events.map(\.kind) }
}

/// Chạm 2 lần vào chỗ cần gõ = đặt con trỏ gõ (cú đầu) rồi mở bàn phím (cú thứ hai không gửi gì sang Mac).
@Suite struct DoubleTapKeyboardTests {
    private func touch(_ id: Int, _ x: Float, _ y: Float, _ phase: TouchPhase, _ t: Int64) -> TouchSample {
        TouchSample(id: id, x: x, y: y, phase: phase, timeMs: t)
    }

    private func engine(doubleTapOpensKeyboard: Bool) -> PointerEngine {
        PointerEngine(settings: PointerSettings(doubleTapOpensKeyboard: doubleTapOpensKeyboard), surfaceWidth: 1000, surfaceHeight: 500)
    }

    @Test func doubleTapClicksOnceThenAsksForTheKeyboard() {
        var e = engine(doubleTapOpensKeyboard: true)
        _ = e.handle(touch(1, 0.3, 0.8, .began, 0))
        do { let out = e.handle(touch(1, 0.3, 0.8, .ended, 50)); #expect(out.map(\.kind) == [.move, .down, .up], "cú đầu đặt con trỏ gõ") }
        do { let r = e.takeKeyboardRequest(); #expect(!r) }
        _ = e.handle(touch(2, 0.3, 0.8, .began, 150))
        do { let out = e.handle(touch(2, 0.3, 0.8, .ended, 200)); #expect(out.isEmpty, "cú thứ hai không double-click (không bôi chọn chữ)") }
        do { let r = e.takeKeyboardRequest(); #expect(r) }
        do { let r = e.takeKeyboardRequest(); #expect(!r, "đọc xong thì xoá") }
        // Chạm tiếp ngay sau đó là click đơn mới, không thành triple-click.
        _ = e.handle(touch(3, 0.3, 0.8, .began, 300))
        do { let out = e.handle(touch(3, 0.3, 0.8, .ended, 350)); #expect(out[1].dx == 1) }
    }

    @Test func settingOffKeepsDoubleClick() {
        var e = engine(doubleTapOpensKeyboard: false)
        _ = e.handle(touch(1, 0.3, 0.8, .began, 0)); _ = e.handle(touch(1, 0.3, 0.8, .ended, 50))
        _ = e.handle(touch(2, 0.3, 0.8, .began, 150))
        do { let out = e.handle(touch(2, 0.3, 0.8, .ended, 200)); #expect(out[1].dx == 2) }
        do { let r = e.takeKeyboardRequest(); #expect(!r) }
    }
}
