/// Zoom + kéo (pan) của video trong view, dùng ở kiểu Bản sao "Giống màn hình Mac": cả màn hình Mac letterbox vừa khung,
/// người dùng phóng to để chạm vào chi tiết nhỏ. Mô hình: điểm `base` (video chưa zoom, như `VideoContentMapper` thấy) ↔ điểm
/// trong view: `view = c + zoom * (base - c) + t` với `c` là tâm view. Zoom 1 = vừa khung; không bao giờ kéo hở mép video.
public struct VideoViewport: Sendable, Equatable {
    public static let maxZoom: Float = 5
    public static let identity = VideoViewport()

    public private(set) var zoom: Float = 1
    public private(set) var translationX: Float = 0
    public private(set) var translationY: Float = 0

    public init() {}

    public var isIdentity: Bool { self == .identity }

    /// Điểm trong view → điểm video chưa zoom (toạ độ đưa cho `VideoContentMapper`).
    public func toBase(x: Float, y: Float, in mapper: VideoContentMapper) -> (x: Float, y: Float) {
        let cx = mapper.viewWidth / 2, cy = mapper.viewHeight / 2
        return (cx + (x - cx - translationX) / zoom, cy + (y - cy - translationY) / zoom)
    }

    /// Như `toBase` nhưng bỏ độ kéo: dành cho trackpad (chỉ cần độ dời), nhờ đó con trỏ chạy ra mép làm video tự kéo theo
    /// cũng không làm ngón đứng yên bị tính thành đang trượt.
    public func toBaseIgnoringPan(x: Float, y: Float, in mapper: VideoContentMapper) -> (x: Float, y: Float) {
        let cx = mapper.viewWidth / 2, cy = mapper.viewHeight / 2
        return (cx + (x - cx) / zoom, cy + (y - cy) / zoom)
    }

    /// Điểm video chưa zoom → điểm trong view.
    public func toView(x: Float, y: Float, in mapper: VideoContentMapper) -> (x: Float, y: Float) {
        let cx = mapper.viewWidth / 2, cy = mapper.viewHeight / 2
        return (cx + zoom * (x - cx) + translationX, cy + zoom * (y - cy) + translationY)
    }

    /// Nhân zoom với `factor`, giữ điểm video đang nằm dưới `focus` (toạ độ view) đứng yên.
    public func zoomed(by factor: Float, around focus: (x: Float, y: Float), in mapper: VideoContentMapper) -> VideoViewport {
        guard factor.isFinite, factor > 0, focus.x.isFinite, focus.y.isFinite else { return self }
        let base = toBase(x: focus.x, y: focus.y, in: mapper)
        var next = self
        next.zoom = min(max(zoom * factor, 1), Self.maxZoom)
        let cx = mapper.viewWidth / 2, cy = mapper.viewHeight / 2
        next.translationX = focus.x - cx - next.zoom * (base.x - cx)
        next.translationY = focus.y - cy - next.zoom * (base.y - cy)
        return next.clamped(in: mapper)
    }

    public func panned(dx: Float, dy: Float, in mapper: VideoContentMapper) -> VideoViewport {
        guard dx.isFinite, dy.isFinite else { return self }
        var next = self
        next.translationX += dx
        next.translationY += dy
        return next.clamped(in: mapper)
    }

    /// Kéo vừa đủ để điểm video `base` nằm trong view, cách mép ít nhất `margin` (con trỏ trackpad chạy ra mép khi đang zoom).
    public func revealing(base: (x: Float, y: Float), margin: Float, in mapper: VideoContentMapper) -> VideoViewport {
        let point = toView(x: base.x, y: base.y, in: mapper)
        guard point.x.isFinite, point.y.isFinite else { return self }
        let dx = Self.shift(point.x, length: mapper.viewWidth, margin: margin)
        let dy = Self.shift(point.y, length: mapper.viewHeight, margin: margin)
        return dx == 0 && dy == 0 ? self : panned(dx: dx, dy: dy, in: mapper)
    }

    /// Ép lại sau khi kích thước view/video đổi (xoay máy): trục nào video đã nhỏ hơn view thì căn giữa.
    public func clamped(in mapper: VideoContentMapper) -> VideoViewport {
        var next = self
        next.translationX = Self.clamp(translationX, zoom: zoom, lo: mapper.originX, hi: mapper.originX + mapper.width, length: mapper.viewWidth)
        next.translationY = Self.clamp(translationY, zoom: zoom, lo: mapper.originY, hi: mapper.originY + mapper.height, length: mapper.viewHeight)
        return next
    }

    private static func shift(_ value: Float, length: Float, margin: Float) -> Float {
        let safe = min(margin, length / 2)
        if value < safe { return safe - value }
        if value > length - safe { return length - safe - value }
        return 0
    }

    private static func clamp(_ t: Float, zoom: Float, lo: Float, hi: Float, length: Float) -> Float {
        let c = length / 2
        let scaledLo = c + zoom * (lo - c), scaledHi = c + zoom * (hi - c)
        if scaledHi - scaledLo <= length { return length / 2 - (scaledLo + scaledHi) / 2 }
        return min(max(t, length - scaledHi), -scaledLo)
    }
}
