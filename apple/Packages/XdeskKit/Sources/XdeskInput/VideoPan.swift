/// Khi bàn phím mở, dịch video lên vừa đủ để vùng người dùng vừa chạm (vị trí con trỏ/ caret) nằm trên bàn phím.
/// Chọn dịch thay vì thu nhỏ vừa khung: giữ nguyên tỉ lệ 1:1 nên chữ vẫn đọc được trên iPhone nằm ngang
/// (thu nhỏ còn khoảng 1/3 chiều cao màn hình).
public enum VideoPan {
    public static let defaultMargin: Float = 28

    /// Độ dịch lên (≥ 0, đơn vị điểm).
    /// - `focusY`: toạ độ y (view, chưa dịch) của vùng cần thấy.
    /// - `obscuredHeight`: chiều cao bàn phím + thanh phím phụ che đáy view.
    /// - `videoBottom`: đáy khung video trong view; không dịch quá mức cần để thấy đáy video.
    public static func offset(focusY: Float, viewHeight: Float, obscuredHeight: Float, videoBottom: Float, margin: Float = defaultMargin) -> Float {
        guard [focusY, viewHeight, obscuredHeight, videoBottom, margin].allSatisfy(\.isFinite), obscuredHeight > 0 else { return 0 }
        let visibleBottom = viewHeight - obscuredHeight
        let needed = focusY + margin - visibleBottom
        let useful = videoBottom - visibleBottom
        return max(0, min(needed, obscuredHeight, useful))
    }
}
