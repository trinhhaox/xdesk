import Testing
@testable import XdeskInput

@Suite struct FloatingControlPlacementTests {
    @Test func defaultIsMiddleOfTrailingEdge() {
        let c = FloatingControlPlacement().center(containerWidth: 400, containerHeight: 800, size: 44)
        #expect(c.x == 400 - 22 - 4 && c.y == 22 + 0.5 * 756)
    }

    @Test func releaseSnapsToNearestSideAndClampsHeight() {
        let left = FloatingControlPlacement.snapped(centerX: 100, centerY: 5000, containerWidth: 400, containerHeight: 800, size: 44)
        #expect(left.side == .leading && left.verticalFraction == 1)
        let right = FloatingControlPlacement.snapped(centerX: 300, centerY: -50, containerWidth: 400, containerHeight: 800, size: 44)
        #expect(right.side == .trailing && right.verticalFraction == 0)
    }

    @Test func nonFiniteFractionFallsBackToMiddleAndRoundTrips() {
        #expect(FloatingControlPlacement(verticalFraction: .nan).verticalFraction == 0.5)
        let p = FloatingControlPlacement(side: .leading, verticalFraction: 0.25)
        let c = p.center(containerWidth: 400, containerHeight: 800, size: 44)
        #expect(FloatingControlPlacement.snapped(centerX: c.x, centerY: c.y, containerWidth: 400, containerHeight: 800, size: 44) == p)
    }
}
