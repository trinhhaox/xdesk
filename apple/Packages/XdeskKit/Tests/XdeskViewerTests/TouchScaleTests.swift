import Testing
@testable import XdeskViewer

@Suite struct TouchScaleTests {
    @Test func iPhoneIsLimitedByMinimumLogicalShortEdge() {
        let m = TouchScale.magnification(pointsWidth: 393, pointsHeight: 852)
        #expect(abs(m - 393.0 / 540.0) < 1e-9)
        let logical = TouchScale.logicalSize(pointsWidth: 393, pointsHeight: 852)
        #expect((logical.width, logical.height) == (540, 1171))
        // Điều khiển 22 pt thành ~16 pt trên viewer (fitDevice scale 3: ~14.7 pt).
        #expect(22 * m > 22 * 2.0 / 3.0)
    }

    @Test func iPadReachesNearTouchTargetLimitedByLongEdge() {
        let m = TouchScale.magnification(pointsWidth: 820, pointsHeight: 1180)
        #expect(abs(m - 820.0 / 540.0) < 1e-9)
        #expect(22 * m >= 33)
    }

    @Test func largeSurfaceReachesIdealTwoTimes() {
        #expect(TouchScale.magnification(pointsWidth: 1600, pointsHeight: 2400) == 2)
    }

    @Test func smallViewerNeverGoesBelowMacOSMinimumShortEdge() {
        let logical = TouchScale.logicalSize(pointsWidth: 300, pointsHeight: 500)
        #expect(logical.width == 540)
    }

    @Test func landscapeKeepsOrientationAndMagnification() {
        let portrait = TouchScale.magnification(pointsWidth: 393, pointsHeight: 852)
        #expect(TouchScale.magnification(pointsWidth: 852, pointsHeight: 393) == portrait)
        let logical = TouchScale.logicalSize(pointsWidth: 852, pointsHeight: 393)
        #expect((logical.width, logical.height) == (1171, 540))
    }
}
