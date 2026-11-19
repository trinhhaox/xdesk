import Foundation

/// Kiểu "Tối ưu thao tác" của chế độ Bản sao: chọn độ phân giải logic thấp cho desktop Mac để nút bấm macOS đủ to cho ngón tay.
/// Công thức (đơn vị điểm của viewer, xấp xỉ kích thước vật lý): điều khiển macOS nhỏ nhất `macControlPoints` (22 pt) phải thành
/// ≥ `minTouchPoints` (44 pt) trên viewer → phóng đại lý tưởng 44/22 = 2×. Desktop macOS không dùng được nếu logic nhỏ hơn
/// 540 pt cạnh ngắn (đo thực trên macOS: mode HiDPI có cạnh ngắn logic ≤ 520 bị macOS từ chối, 540 thì được; cũng đủ cho menu bar, cửa sổ tối thiểu) nên phóng đại bị chặn ở `short/540` và `long/640`; với điện thoại nhỏ giá trị có thể < 1 (logic lớn hơn điểm viewer) vì sàn macOS là ràng buộc cứng.
public enum TouchScale {
    public static let macControlPoints = 22.0
    public static let minTouchPoints = 44.0
    public static let minLogicalShort = 540.0
    public static let minLogicalLong = 640.0

    /// Số lần phóng đại giao diện Mac trên viewer so với kích thước logic.
    public static func magnification(pointsWidth: Double, pointsHeight: Double) -> Double {
        let short = min(pointsWidth, pointsHeight), long = max(pointsWidth, pointsHeight)
        let ideal = minTouchPoints / macControlPoints
        return min(ideal, short / minLogicalShort, long / minLogicalLong)
    }

    /// Kích thước logic (điểm macOS) của desktop Mac, giữ chiều xoay và tỉ lệ viewer; mỗi cạnh làm tròn.
    public static func logicalSize(pointsWidth: Double, pointsHeight: Double) -> (width: Double, height: Double) {
        let m = magnification(pointsWidth: pointsWidth, pointsHeight: pointsHeight)
        return ((pointsWidth / m).rounded(), (pointsHeight / m).rounded())
    }
}
