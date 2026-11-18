import CoreGraphics
import Testing
@testable import Xdesk

@Suite struct CoordinateMapperTests {
    private func mapper(_ rect: CGRect) -> CoordinateMapper { CoordinateMapper(bounds: { rect }) }

    @Test func extendedDisplayToTheRight() {
        let m = mapper(CGRect(x: 1512, y: 0, width: 1280, height: 800))
        #expect(m.point(x: 0, y: 0) == CGPoint(x: 1512, y: 0))
        #expect(m.point(x: 0.5, y: 0.5) == CGPoint(x: 1512 + 640, y: 400))
    }

    @Test func negativeOriginLeftOfMain() {
        let m = mapper(CGRect(x: -1280, y: -200, width: 1280, height: 800))
        #expect(m.point(x: 0, y: 0) == CGPoint(x: -1280, y: -200))
        #expect(m.point(x: 0.25, y: 0.75) == CGPoint(x: -1280 + 320, y: -200 + 600))
        let p = m.point(x: 1, y: 1)
        #expect(p.x < 0 && p.y < 600)
        #expect(abs(p.x - -0.5) < 0.0001 && abs(p.y - 599.5) < 0.0001)
    }

    @Test func retinaDisplayUsesPointsNotPixels() {
        // 2560×1600 px ở scale 2 → bounds 1280×800 điểm.
        let m = mapper(CGRect(x: 0, y: 0, width: 1280, height: 800))
        #expect(m.point(x: 0.5, y: 0.5) == CGPoint(x: 640, y: 400))
        let p = m.point(x: 0.125, y: 0.875)
        #expect(p == CGPoint(x: 160, y: 700))
    }

    @Test func mirrorModeVirtualDisplayIsMainAtOrigin() {
        let m = mapper(CGRect(x: 0, y: 0, width: 1194, height: 834))
        #expect(m.point(x: 0.5, y: 0.5) == CGPoint(x: 597, y: 417))
    }

    @Test func outOfRangeIsClampedInsideDisplay() {
        let m = mapper(CGRect(x: 100, y: 50, width: 400, height: 300))
        #expect(m.point(x: -1, y: 2) == CGPoint(x: 100, y: 50 + 299.5))
    }

    @Test func followsBoundsChanges() {
        let box = BoundsBox(CGRect(x: 0, y: 0, width: 100, height: 100))
        let m = CoordinateMapper(bounds: { box.value })
        #expect(m.point(x: 0.5, y: 0.5) == CGPoint(x: 50, y: 50))
        box.value = CGRect(x: -100, y: 0, width: 100, height: 100)
        #expect(m.point(x: 0.5, y: 0.5) == CGPoint(x: -50, y: 50))
    }
}

private final class BoundsBox: @unchecked Sendable {
    var value: CGRect
    init(_ value: CGRect) { self.value = value }
}
