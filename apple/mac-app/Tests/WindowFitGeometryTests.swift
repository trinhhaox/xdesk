import CoreGraphics
import Testing
@testable import Xdesk

@Suite struct WindowFitGeometryTests {
    private let target = CGRect(x: 0, y: 38, width: 645, height: 1360)

    @Test func fillsTargetWhenWindowCanShrink() {
        #expect(WindowFitGeometry.frame(minSize: CGSize(width: 300, height: 200), in: target) == target)
    }

    @Test func keepsMinimumSizeAndAnchorsTopLeftWhenWindowCannotShrink() {
        let frame = WindowFitGeometry.frame(minSize: CGSize(width: 800, height: 400), in: target)
        #expect(frame == CGRect(x: target.minX, y: target.minY, width: 800, height: 1360))
    }

    @Test func anchorsTopLeftWhenWindowIsLargerOnBothAxes() {
        let frame = WindowFitGeometry.frame(minSize: CGSize(width: 900, height: 1500), in: target)
        #expect(frame == CGRect(x: target.minX, y: target.minY, width: 900, height: 1500))
    }

    @Test func refitsWindowsThatDriftedOffScreenButNotAnchoredOversizedOnes() {
        #expect(WindowFitGeometry.needsRefit(CGRect(x: -200, y: 38, width: 600, height: 800), in: target))
        #expect(WindowFitGeometry.needsRefit(CGRect(x: 100, y: 38, width: 600, height: 800), in: target))
        #expect(!WindowFitGeometry.needsRefit(CGRect(x: 0, y: 38, width: 900, height: 800), in: target))
        #expect(!WindowFitGeometry.needsRefit(target, in: target))
        #expect(WindowFitGeometry.needsRefit(CGRect(x: 0, y: 10, width: 600, height: 800), in: target))
    }

    @Test func convertsVisibleFrameToTopLeftAXCoordinates() {
        // Màn hình ảo 645×1398: menu bar 24 pt ở trên, visibleFrame cao 1374 gốc dưới-trái.
        let ax = WindowFitGeometry.axRect(fromVisibleFrame: CGRect(x: 0, y: 0, width: 645, height: 1374), primaryHeight: 1398)
        #expect(ax == CGRect(x: 0, y: 24, width: 645, height: 1374))
    }

    @Test func ledgerRemembersOnlyTheFirstFrameAndDrainsOnce() {
        var ledger = WindowFrameLedger<Int>()
        ledger.remember(1, frame: CGRect(x: 10, y: 20, width: 300, height: 200))
        ledger.remember(1, frame: CGRect(x: 0, y: 0, width: 645, height: 1360))
        ledger.remember(2, frame: CGRect(x: 5, y: 5, width: 50, height: 50))
        #expect(ledger.count == 2 && ledger.contains(1) && !ledger.contains(3))
        let drained = ledger.drain()
        #expect(drained.count == 2)
        #expect(drained.first { $0.key == 1 }?.frame == CGRect(x: 10, y: 20, width: 300, height: 200))
        #expect(ledger.count == 0 && ledger.drain().isEmpty)
    }
}
