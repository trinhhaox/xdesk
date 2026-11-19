/// Vị trí nút điều khiển nổi trên màn stream: dính mép trái/phải (không dính mép trên/dưới để khỏi che menu bar,
/// Dock và thanh tiêu đề của Mac), `verticalFraction` 0…1 dọc theo đoạn di chuyển được. Mặc định giữa mép phải.
public struct FloatingControlPlacement: Sendable, Equatable {
    public enum Side: String, Sendable { case leading, trailing }

    public var side: Side
    public var verticalFraction: Float

    public init(side: Side = .trailing, verticalFraction: Float = 0.5) {
        self.side = side
        self.verticalFraction = verticalFraction.isFinite ? min(max(verticalFraction, 0), 1) : 0.5
    }

    /// Tâm nút (toạ độ container) cách mép `margin`.
    public func center(containerWidth: Float, containerHeight: Float, size: Float, margin: Float = 4) -> (x: Float, y: Float) {
        let half = size / 2
        let x = side == .trailing ? containerWidth - half - margin : half + margin
        return (x, half + verticalFraction * max(0, containerHeight - size))
    }

    /// Thả tay tại `center`: dính mép gần nhất theo chiều ngang, giữ độ cao (ép vào container).
    public static func snapped(centerX: Float, centerY: Float, containerWidth: Float, containerHeight: Float, size: Float) -> FloatingControlPlacement {
        let range = max(1, containerHeight - size)
        return FloatingControlPlacement(side: centerX > containerWidth / 2 ? .trailing : .leading, verticalFraction: (centerY - size / 2) / range)
    }
}
