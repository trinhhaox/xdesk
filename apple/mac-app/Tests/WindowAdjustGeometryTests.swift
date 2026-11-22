import CoreGraphics
import Testing
import XdeskWire
@testable import Xdesk

@Suite struct WindowAdjustGeometryTests {
    /// Màn hình ảo 1000×2000 đặt bên phải màn chính (gốc x = 1440), viewer xem khung 500×1000 điểm (tỉ lệ 2×).
    private let viewport = WindowViewport(displayBounds: CGRect(x: 1440, y: -100, width: 1000, height: 2000), viewerSize: CGSize(width: 500, height: 1000))
    private let visible = CGRect(x: 1440, y: -76, width: 1000, height: 1900)
    private let frame = CGRect(x: 1600, y: 200, width: 400, height: 300)

    @Test func viewerFrameRoundTripsThroughScreenCoordinates() {
        let viewer = viewport.viewerFrame(fromScreen: frame)
        #expect(viewer == WindowFrame(x: 80, y: 150, w: 200, h: 150))
        let origin = viewport.screenPoint(x: viewer.x, y: viewer.y)
        let size = viewport.screenSize(w: viewer.w, h: viewer.h)
        #expect(abs(origin.x - frame.minX) < 0.01 && abs(origin.y - frame.minY) < 0.01)
        #expect(size == frame.size)
    }

    @Test func pointOutsideStreamIsClampedIntoDisplay() {
        let p = viewport.screenPoint(x: 9999, y: -50)
        #expect(p.x < viewport.displayBounds.maxX && p.x > viewport.displayBounds.maxX - 1)
        #expect(p.y == viewport.displayBounds.minY)
    }

    @Test func moveIsScaledAndClampedInsideVisibleArea() {
        let delta = viewport.screenDelta(dx: 10, dy: -5)
        #expect(delta == CGPoint(x: 20, y: -10))
        #expect(WindowAdjustGeometry.moved(frame, by: delta, in: visible) == frame.offsetBy(dx: 20, dy: -10))
        let far = WindowAdjustGeometry.moved(frame, by: CGPoint(x: 99_999, y: -99_999), in: visible)
        #expect(far == CGRect(x: visible.maxX - 400, y: visible.minY, width: 400, height: 300))
    }

    @Test func resizeKeepsCentreAndClampsToMinAndVisible() {
        let grown = WindowAdjustGeometry.resized(frame, to: CGSize(width: 600, height: 500), in: visible)
        #expect(grown.midX == frame.midX && grown.midY == frame.midY && grown.size == CGSize(width: 600, height: 500))
        let tiny = WindowAdjustGeometry.resized(frame, to: CGSize(width: 10, height: 10), in: visible)
        #expect(tiny.size == WindowAdjustGeometry.minSize)
        let huge = WindowAdjustGeometry.resized(frame, to: CGSize(width: 99_999, height: 99_999), in: visible)
        #expect(huge == visible)
    }

    @Test func resizeFallsBackToTopLeftWhenCentreOverflows() {
        let nearEdge = CGRect(x: visible.maxX - 220, y: visible.minY + 10, width: 200, height: 150)
        let result = WindowAdjustGeometry.resized(nearEdge, to: CGSize(width: 400, height: 150), in: visible)
        #expect(visible.contains(result) && result.size == CGSize(width: 400, height: 150))
    }

    @Test func presetsFillHalvesCenterAndRestore() {
        func make(_ p: WindowPreset, original: CGRect? = nil, canResize: Bool = true) -> CGRect {
            WindowAdjustGeometry.preset(p, current: frame, visible: visible, original: original, canResize: canResize)
        }
        #expect(make(.fill) == visible)
        #expect(make(.left) == CGRect(x: visible.minX, y: visible.minY, width: 500, height: visible.height))
        #expect(make(.right) == CGRect(x: visible.midX, y: visible.minY, width: 500, height: visible.height))
        let center = make(.center)
        #expect(center.midX == visible.midX && center.midY == visible.midY && center.width == 700 && center.height == 1330)
        let original = CGRect(x: 1500, y: 100, width: 300, height: 300)
        #expect(make(.restore, original: original) == original)
        #expect(make(.restore) == frame)
    }

    @Test func nonResizableWindowOnlyMovesOnPresets() {
        let moved = WindowAdjustGeometry.preset(.right, current: frame, visible: visible, original: nil, canResize: false)
        #expect(moved.size == frame.size && moved.midX == visible.midX + 250 && visible.contains(moved))
    }

    @Test func accumulatorMergesMovesKeepsLatestResizeAndPresetWins() {
        var acc = WindowAdjustAccumulator()
        acc.add(.move(windowId: 1, dx: 1, dy: 2)); acc.add(.move(windowId: 1, dx: 3, dy: -1))
        acc.add(.resize(windowId: 1, w: 300, h: 300)); acc.add(.resize(windowId: 1, w: 400, h: 350))
        acc.add(.move(windowId: 1, dx: 5, dy: 5))
        let first = acc.take()
        #expect(first == [.move(windowId: 1, dx: 4, dy: 1), .resize(windowId: 1, w: 400, h: 350), .move(windowId: 1, dx: 5, dy: 5)])
        #expect(acc.isEmpty)
        acc.add(.move(windowId: 1, dx: 1, dy: 1)); acc.add(.move(windowId: 2, dx: 1, dy: 1)); acc.add(.preset(windowId: 1, .fill))
        let second = acc.take()
        #expect(second == [.move(windowId: 2, dx: 1, dy: 1), .preset(windowId: 1, .fill)])
    }

    @Test func rateLimiterAllows60PerSecondButNeverDropsPresets() {
        var limiter = WindowAdjustRateLimiter()
        let move = WindowAdjust.move(windowId: 1, dx: 1, dy: 1)
        var allowed = 0
        for i in 0..<100 where limiter.allow(move, nowMs: Int64(i * 5)) { allowed += 1 }
        #expect(allowed == 60)
        let preset = limiter.allow(.preset(windowId: 1, .left), nowMs: 500)
        let afterWindow = limiter.allow(move, nowMs: 1_600)
        #expect(preset && afterWindow)
    }
}
