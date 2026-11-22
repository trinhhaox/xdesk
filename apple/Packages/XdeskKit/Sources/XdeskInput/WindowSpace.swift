import CoreGraphics
import XdeskWire

/// Đổi qua lại giữa điểm trong view (có letterbox + zoom/kéo) và hệ toạ độ của `window.pick`/`window.adjust`:
/// kích thước khung hình giải mã (px) ÷ `display.config.scale` = `wireWidth` × `wireHeight`. Cùng phép đổi với chạm trực tiếp
/// (`VideoViewport` → `VideoContentMapper`), nên khung vẽ luôn trùng cửa sổ thật dưới ngón tay.
public struct WindowSpace: Sendable, Equatable {
    public let wireWidth: Double
    public let wireHeight: Double
    public let mapper: VideoContentMapper
    public let viewport: VideoViewport

    /// `nil` khi kích thước hệ toạ độ host không hợp lệ.
    public init?(wireWidth: Double, wireHeight: Double, mapper: VideoContentMapper, viewport: VideoViewport) {
        guard wireWidth.isFinite, wireHeight.isFinite, wireWidth > 0, wireHeight > 0 else { return nil }
        self.wireWidth = wireWidth
        self.wireHeight = wireHeight
        self.mapper = mapper
        self.viewport = viewport
    }

    /// Số điểm view trên mỗi điểm host (đã tính zoom).
    public var viewPerWireX: Double { Double(mapper.width * viewport.zoom) / wireWidth }
    public var viewPerWireY: Double { Double(mapper.height * viewport.zoom) / wireHeight }

    /// Điểm view → điểm host; `nil` khi chạm vào dải đen letterbox.
    public func toWire(x: Double, y: Double) -> (x: Double, y: Double)? {
        let base = viewport.toBase(x: Float(x), y: Float(y), in: mapper)
        guard let n = mapper.normalize(x: base.x, y: base.y) else { return nil }
        return (Double(n.x) * wireWidth, Double(n.y) * wireHeight)
    }

    /// Điểm host → điểm view.
    public func toView(x: Double, y: Double) -> CGPoint {
        let base = (x: mapper.originX + Float(x / wireWidth) * mapper.width, y: mapper.originY + Float(y / wireHeight) * mapper.height)
        let point = viewport.toView(x: base.x, y: base.y, in: mapper)
        return CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
    }

    public func viewRect(_ frame: WindowFrame) -> CGRect {
        let origin = toView(x: frame.x, y: frame.y)
        return CGRect(x: origin.x, y: origin.y, width: frame.w * viewPerWireX, height: frame.h * viewPerWireY)
    }

    /// Độ dời trên view (điểm) → độ dời theo hệ toạ độ host.
    public func wireDelta(viewDx: Double, viewDy: Double) -> (dx: Double, dy: Double) {
        (viewDx / viewPerWireX, viewDy / viewPerWireY)
    }
}
