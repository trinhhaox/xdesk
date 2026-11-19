import Testing
@testable import XdeskInput

/// Mac 16:10 (2560×1600) trong iPhone dọc 393×852 pt: video letterbox, rộng kín view.
@Suite struct VideoViewportTests {
    private let portrait = VideoContentMapper(viewWidth: 393, viewHeight: 852, contentWidth: 2560, contentHeight: 1600)!

    private func near(_ a: (x: Float, y: Float), _ b: (x: Float, y: Float), _ eps: Float = 0.01) -> Bool {
        abs(a.x - b.x) < eps && abs(a.y - b.y) < eps
    }

    @Test func identityMapsOneToOne() {
        let base = VideoViewport.identity.toBase(x: 100, y: 400, in: portrait)
        #expect(near(base, (100, 400)))
    }

    @Test func zoomKeepsFocusPointFixedAndMapsToMacCoordinates() throws {
        let focus: (x: Float, y: Float) = (300, 426)
        let before = try #require(portrait.normalize(x: focus.x, y: focus.y))
        let zoomed = VideoViewport.identity.zoomed(by: 3, around: focus, in: portrait)
        #expect(zoomed.zoom == 3)
        let base = zoomed.toBase(x: focus.x, y: focus.y, in: portrait)
        let after = try #require(portrait.normalize(x: base.x, y: base.y))
        #expect(abs(before.x - after.x) < 1e-4 && abs(before.y - after.y) < 1e-4)
    }

    @Test func zoomedCornersReachMacCorners() throws {
        // Zoom 4× rồi kéo hết cỡ sang trái-trên: góc trên-trái view = ~ (0,0) ... ngược lại góc phải = (1, y) trên Mac.
        var viewport = VideoViewport.identity.zoomed(by: 4, around: (196.5, 426), in: portrait)
        viewport = viewport.panned(dx: -10_000, dy: 0, in: portrait)
        let right = viewport.toBase(x: 393, y: 426, in: portrait)
        let normalized = try #require(portrait.normalize(x: right.x, y: right.y))
        #expect(abs(normalized.x - 1) < 1e-4)
        viewport = viewport.panned(dx: 10_000, dy: 0, in: portrait)
        let left = viewport.toBase(x: 0, y: 426, in: portrait)
        #expect(abs(try #require(portrait.normalize(x: left.x, y: left.y)).x) < 1e-4)
    }

    @Test func roundTripBaseView() {
        let viewport = VideoViewport.identity.zoomed(by: 2.5, around: (120, 300), in: portrait)
        let view = viewport.toView(x: 77, y: 413, in: portrait)
        #expect(near(viewport.toBase(x: view.x, y: view.y, in: portrait), (77, 413)))
    }

    @Test func zoomIsClampedToRange() {
        #expect(VideoViewport.identity.zoomed(by: 100, around: (10, 10), in: portrait).zoom == VideoViewport.maxZoom)
        #expect(VideoViewport.identity.zoomed(by: 0.1, around: (10, 10), in: portrait).isIdentity)
        #expect(VideoViewport.identity.zoomed(by: .nan, around: (10, 10), in: portrait).isIdentity)
    }

    @Test func panCannotExposeGapsAndShortAxisStaysCentered() {
        let viewport = VideoViewport.identity.zoomed(by: 2, around: (196.5, 426), in: portrait)
        // Video cao 245 pt; zoom 2 = 490 < 852 → trục dọc luôn căn giữa dù kéo.
        let dragged = viewport.panned(dx: 5000, dy: 5000, in: portrait)
        #expect(dragged.translationY == 0)
        #expect(dragged.translationX == 196.5)  // (zoom-1) * 393 / 2: mép trái video chạm mép trái view
    }

    @Test func rotationReclampsToNewGeometry() {
        let zoomed = VideoViewport.identity.zoomed(by: 4, around: (300, 426), in: portrait)
        let landscape = VideoContentMapper(viewWidth: 852, viewHeight: 393, contentWidth: 2560, contentHeight: 1600)!
        let fixed = zoomed.clamped(in: landscape)
        let corner = fixed.toBase(x: 0, y: 0, in: landscape)
        #expect(corner.x >= landscape.originX - 0.01 && corner.y >= landscape.originY - 0.01)
    }

    @Test func revealingScrollsTheCursorIntoView() {
        let zoomed = VideoViewport.identity.zoomed(by: 4, around: (196.5, 426), in: portrait).panned(dx: 10_000, dy: 0, in: portrait)
        let target = portrait.originX + portrait.width * 0.9  // gần mép phải video, đang ngoài view
        let revealed = zoomed.revealing(base: (target, 426), margin: 24, in: portrait)
        let view = revealed.toView(x: target, y: 426, in: portrait)
        #expect(view.x >= 24 - 0.01 && view.x <= 393 - 24 + 0.01)
    }

    @Test func trackpadMappingIgnoresPan() {
        let zoomed = VideoViewport.identity.zoomed(by: 4, around: (300, 426), in: portrait)
        let panned = zoomed.panned(dx: -80, dy: 0, in: portrait)
        #expect(panned != zoomed)
        let a = zoomed.toBaseIgnoringPan(x: 100, y: 200, in: portrait), b = panned.toBaseIgnoringPan(x: 100, y: 200, in: portrait)
        #expect(near(a, b))
    }

    @Test func trackpadDeltasShrinkWithZoom() {
        // Ngón trượt 100 pt: không zoom = 100 pt video; zoom 4× = 25 pt video → con trỏ chính xác hơn.
        let viewport = VideoViewport.identity.zoomed(by: 4, around: (196.5, 426), in: portrait)
        let a = viewport.toBase(x: 100, y: 426, in: portrait), b = viewport.toBase(x: 200, y: 426, in: portrait)
        #expect(abs((b.x - a.x) - 25) < 0.01)
    }
}
