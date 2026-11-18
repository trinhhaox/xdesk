import CoreGraphics

/// Toạ độ chuẩn hoá 0…1 trên màn hình được capture → điểm toàn cục (hệ CG, gốc trên-trái màn hình chính).
/// Đọc `CGDisplayBounds` mỗi lần nên theo kịp khi màn hình đổi vị trí; gốc âm (màn hình đặt bên trái/trên) và
/// scale 2× đều đúng vì bounds tính theo điểm.
struct CoordinateMapper: Sendable {
    private let bounds: @Sendable () -> CGRect

    init(displayID: CGDirectDisplayID) {
        bounds = { CGDisplayBounds(displayID) }
    }

    init(bounds: @escaping @Sendable () -> CGRect) { self.bounds = bounds }

    func point(x: Float, y: Float) -> CGPoint {
        let rect = bounds()
        // Điểm nằm đúng cạnh phải/dưới thuộc màn hình bên cạnh; kẹp vào trong nửa pixel.
        let px = min(max(CGFloat(x), 0), 1) * rect.width
        let py = min(max(CGFloat(y), 0), 1) * rect.height
        return CGPoint(x: rect.minX + min(px, max(0, rect.width - 0.5)), y: rect.minY + min(py, max(0, rect.height - 0.5)))
    }
}
