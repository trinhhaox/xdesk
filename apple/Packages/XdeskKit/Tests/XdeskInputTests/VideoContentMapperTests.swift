import Testing
@testable import XdeskInput

@Suite struct VideoContentMapperTests {
    @Test func pillarboxedWhenViewIsWiderThanContent() throws {
        // View 2000x1000, nội dung 16:10 → khung 1600x1000 căn giữa, dải đen 200 mỗi bên.
        let mapper = try #require(VideoContentMapper(viewWidth: 2000, viewHeight: 1000, contentWidth: 1920, contentHeight: 1200))
        #expect(mapper.originX == 200 && mapper.width == 1600 && mapper.originY == 0 && mapper.height == 1000)
        #expect(mapper.normalize(x: 100, y: 500) == nil)
        #expect(mapper.normalize(x: 1900, y: 500) == nil)
        let centre = try #require(mapper.normalize(x: 1000, y: 500))
        #expect(centre.x == 0.5 && centre.y == 0.5)
        let corner = try #require(mapper.normalize(x: 200, y: 0))
        #expect(corner.x == 0 && corner.y == 0)
    }

    @Test func letterboxedWhenViewIsTallerThanContent() throws {
        // iPhone dọc 400x800, nội dung 16:10 → khung 400x250, lệch xuống 275.
        let mapper = try #require(VideoContentMapper(viewWidth: 400, viewHeight: 800, contentWidth: 1920, contentHeight: 1200))
        #expect(mapper.originY == 275 && mapper.height == 250)
        #expect(mapper.normalize(x: 200, y: 100) == nil)
        let point = try #require(mapper.normalize(x: 100, y: 337.5))
        #expect(point.x == 0.25 && point.y == 0.25)
    }

    @Test func clampingKeepsDragInsideFrame() throws {
        let mapper = try #require(VideoContentMapper(viewWidth: 400, viewHeight: 800, contentWidth: 1920, contentHeight: 1200))
        let out = try #require(mapper.normalize(x: -50, y: 900, clamping: true))
        #expect(out.x == 0 && out.y == 1)
    }

    @Test func rejectsInvalidSizes() {
        #expect(VideoContentMapper(viewWidth: 0, viewHeight: 100, contentWidth: 16, contentHeight: 10) == nil)
        #expect(VideoContentMapper(viewWidth: 100, viewHeight: 100, contentWidth: 16, contentHeight: .nan) == nil)
        #expect(VideoContentMapper(viewWidth: 100, viewHeight: 100, contentWidth: 0, contentHeight: 10) == nil)
    }
}
