import Testing
@testable import Xdesk

@Suite struct DisplayArrangementTests {
    @Test func originPlacesVirtualDisplayOnRequestedSide() {
        let base: (width: Int32, height: Int32) = (1728, 1117)
        let virtual: (width: Int32, height: Int32) = (1280, 720)

        let right = DisplayArrangement.origin(for: .right, baseSize: base, newSize: virtual)
        #expect(right.x == 1728 && right.y == 0)

        let left = DisplayArrangement.origin(for: .left, baseSize: base, newSize: virtual)
        #expect(left.x == -1280 && left.y == 0)

        let top = DisplayArrangement.origin(for: .top, baseSize: base, newSize: virtual)
        #expect(top.x == 0 && top.y == -720)

        let bottom = DisplayArrangement.origin(for: .bottom, baseSize: base, newSize: virtual)
        #expect(bottom.x == 0 && bottom.y == 1117)
    }
}
