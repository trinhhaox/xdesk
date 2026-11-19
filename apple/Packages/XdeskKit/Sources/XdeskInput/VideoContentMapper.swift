/// Đổi toạ độ trong view (gốc trên-trái, đơn vị điểm) sang 0…1 trên khung video thật.
/// Video letterbox (aspect-fit) nên dải đen hai bên không phải là màn hình host.
public struct VideoContentMapper: Sendable, Equatable {
    public let viewWidth: Float
    public let viewHeight: Float
    public let originX: Float
    public let originY: Float
    public let width: Float
    public let height: Float

    /// `nil` khi kích thước view hoặc nội dung không hợp lệ (≤ 0, không hữu hạn).
    public init?(viewWidth: Float, viewHeight: Float, contentWidth: Float, contentHeight: Float) {
        let sizes = [viewWidth, viewHeight, contentWidth, contentHeight]
        guard sizes.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        self.viewWidth = viewWidth
        self.viewHeight = viewHeight
        let scale = min(viewWidth / contentWidth, viewHeight / contentHeight)
        width = contentWidth * scale
        height = contentHeight * scale
        originX = (viewWidth - width) / 2
        originY = (viewHeight - height) / 2
    }

    /// `clamping` = false: chạm vào dải đen → `nil`. `clamping` = true: ép vào mép khung (đang kéo ra ngoài).
    public func normalize(x: Float, y: Float, clamping: Bool = false) -> (x: Float, y: Float)? {
        let nx = (x - originX) / width, ny = (y - originY) / height
        guard nx.isFinite, ny.isFinite else { return nil }
        if clamping { return (min(1, max(0, nx)), min(1, max(0, ny))) }
        guard (0...1).contains(nx), (0...1).contains(ny) else { return nil }
        return (nx, ny)
    }

    /// Không ép vào khung: ngón trượt qua dải đen vẫn cho delta đúng (dùng cho trackpad, chỉ cần độ dời).
    public func normalizeUnbounded(x: Float, y: Float) -> (x: Float, y: Float) {
        ((x - originX) / width, (y - originY) / height)
    }
}
