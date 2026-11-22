import Testing
import XdeskWire
@testable import XdeskInput

@Suite struct WindowSpaceTests {
    // View 2000x1000, video 1920x1200 px → khung 1600x1000 căn giữa (dải đen 200 hai bên); scale 2 → host 960x600.
    private func space(zoomed: Bool = false) throws -> WindowSpace {
        let mapper = try #require(VideoContentMapper(viewWidth: 2000, viewHeight: 1000, contentWidth: 1920, contentHeight: 1200))
        let viewport = zoomed ? VideoViewport.identity.zoomed(by: 2, around: (x: 1000, y: 500), in: mapper) : .identity
        return try #require(WindowSpace(wireWidth: 960, wireHeight: 600, mapper: mapper, viewport: viewport))
    }

    @Test func letterboxMapsCentreAndRejectsBlackBars() throws {
        let s = try space()
        let centre = try #require(s.toWire(x: 1000, y: 500))
        #expect(centre.x == 480 && centre.y == 300)
        #expect(s.toWire(x: 100, y: 500) == nil)
        let corner = try #require(s.toWire(x: 200, y: 0))
        #expect(corner.x == 0 && corner.y == 0)
    }

    @Test func zoomScalesAroundFocus() throws {
        let s = try space(zoomed: true)
        let p = try #require(s.toWire(x: 1400, y: 500))
        #expect(abs(p.x - 600) < 0.01 && abs(p.y - 300) < 0.01)
        #expect(abs(s.viewPerWireX - 1600 * 2 / 960) < 1e-6)
    }

    @Test func wireToViewRoundTrips() throws {
        for s in [try space(), try space(zoomed: true)] {
            let view = s.toView(x: 300, y: 120)
            let back = try #require(s.toWire(x: Double(view.x), y: Double(view.y)))
            #expect(abs(back.x - 300) < 0.01 && abs(back.y - 120) < 0.01)
        }
    }

    @Test func viewRectScalesFrame() throws {
        let rect = try space().viewRect(WindowFrame(x: 0, y: 0, w: 480, h: 300))
        #expect(rect.minX == 200 && rect.minY == 0 && abs(rect.width - 800) < 0.01 && abs(rect.height - 500) < 0.01)
    }

    @Test func wireDeltaDividesByScale() throws {
        let d = try space(zoomed: true).wireDelta(viewDx: 100, viewDy: 100)
        #expect(abs(d.dx - 100 / (3200.0 / 960)) < 1e-6 && abs(d.dy - 100 / (2000.0 / 600)) < 1e-6)
    }

    @Test func invalidWireSizeIsNil() throws {
        let mapper = try #require(VideoContentMapper(viewWidth: 100, viewHeight: 100, contentWidth: 100, contentHeight: 100))
        #expect(WindowSpace(wireWidth: 0, wireHeight: 10, mapper: mapper, viewport: .identity) == nil)
    }
}

@Suite struct WindowGestureMathTests {
    private let frame = WindowFrame(x: 100, y: 100, w: 400, h: 300)

    @Test func dragMovesByDelta() {
        #expect(WindowGestureMath.moved(frame, dx: 30, dy: -10) == WindowFrame(x: 130, y: 90, w: 400, h: 300))
    }

    @Test func pinchResizesAroundCentre() {
        let next = WindowGestureMath.pinched(frame, scale: 1.5, maxWidth: 960, maxHeight: 600)
        #expect(next == WindowFrame(x: 0, y: 25, w: 600, h: 450))
    }

    @Test func pinchClampsToMinimumKeepingAspect() {
        let next = WindowGestureMath.pinched(frame, scale: 0.1, maxWidth: 960, maxHeight: 600)
        #expect(next == WindowFrame(x: 200, y: 175, w: 200, h: 150))
    }

    @Test func pinchClampsToDisplay() {
        let next = WindowGestureMath.pinched(frame, scale: 5, maxWidth: 960, maxHeight: 600)
        #expect(next.w == 800 && next.h == 600)
    }

    @Test func cornerDragAnchorsOppositeCorner() {
        #expect(WindowGestureMath.cornerDragged(frame, corner: .topLeft, dx: 50, dy: 20) == WindowFrame(x: 150, y: 120, w: 350, h: 280))
        #expect(WindowGestureMath.cornerDragged(frame, corner: .bottomRight, dx: 40, dy: -10) == WindowFrame(x: 100, y: 100, w: 440, h: 290))
        #expect(WindowGestureMath.cornerDragged(frame, corner: .topRight, dx: 10, dy: -30) == WindowFrame(x: 100, y: 70, w: 410, h: 330))
    }

    @Test func cornerDragClampsMinimum() {
        let next = WindowGestureMath.cornerDragged(frame, corner: .topLeft, dx: 300, dy: 300)
        #expect(next == WindowFrame(x: 300, y: 250, w: 200, h: 150))
    }

    @Test func planMoveOnlyIsOneMove() {
        let plan = WindowGestureMath.plan(windowId: 7, from: frame, to: WindowGestureMath.moved(frame, dx: 30, dy: -10))
        #expect(plan.ops == [.move(windowId: 7, dx: 30, dy: -10)])
        #expect(plan.applied == WindowFrame(x: 130, y: 90, w: 400, h: 300))
    }

    @Test func planResizeThenMoveCentre() {
        let target = WindowFrame(x: 100, y: 100, w: 500, h: 400)
        let plan = WindowGestureMath.plan(windowId: 7, from: frame, to: target)
        #expect(plan.ops == [.resize(windowId: 7, w: 500, h: 400), .move(windowId: 7, dx: 50, dy: 50)])
        #expect(plan.applied == target)
    }

    @Test func planKeepsSubThresholdResidual() {
        let plan = WindowGestureMath.plan(windowId: 7, from: frame, to: WindowGestureMath.moved(frame, dx: 0.1, dy: 0))
        #expect(plan.ops.isEmpty && plan.applied == frame)
    }

    @Test func cornerHitPicksNearestWithinRadius() {
        let corners: [WindowCorner: (x: Double, y: Double)] = [.topLeft: (0, 0), .topRight: (100, 0), .bottomLeft: (0, 100), .bottomRight: (100, 100)]
        #expect(WindowGestureMath.corner(at: (x: 95, y: 8), corners: corners, radius: 24) == .topRight)
        #expect(WindowGestureMath.corner(at: (x: 50, y: 50), corners: corners, radius: 24) == nil)
    }
}
