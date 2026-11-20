public enum TouchPhase: Sendable, Equatable {
    case began, moved, ended, cancelled
}

/// Một mẫu chạm trừu tượng: toạ độ chuẩn hoá 0…1 trên khung video, thời gian đơn điệu (ms).
public struct TouchSample: Sendable, Equatable {
    public var id: Int
    public var x: Float
    public var y: Float
    public var phase: TouchPhase
    public var timeMs: Int64

    public init(id: Int, x: Float, y: Float, phase: TouchPhase, timeMs: Int64) {
        self.id = id; self.x = x; self.y = y; self.phase = phase; self.timeMs = timeMs
    }
}

public struct GestureConfig: Sendable, Equatable {
    /// Kích thước màn hình host theo điểm; đổi delta chuẩn hoá → pixel và đo ngưỡng di chuyển.
    public var surfaceWidth: Float
    public var surfaceHeight: Float
    public var longPressMs: Int64 = 500
    public var doubleTapMs: Int64 = 300
    /// Hai ngón chạm rồi nhả trong khoảng này (không trượt) = click phải.
    public var twoFingerTapMs: Int64 = 300
    /// Di chuyển dưới ngưỡng này (điểm host) vẫn tính là chạm.
    public var slop: Float = 8
    /// Ngưỡng chạm tính theo điểm trên màn hình điện thoại: ngón tay rung ~10 điểm là bình thường.
    public var viewSlop: Float = 10
    /// Số điểm host ứng với một điểm màn hình điện thoại (theo cỡ video đang hiện, kể cả zoom); 0 = chưa biết.
    /// Màn Mac lớn hiện trên điện thoại nhỏ thì 8 điểm host chỉ còn ~3 điểm dưới ngón: chạm dễ bị hiểu thành vuốt.
    public var hostPointsPerViewPoint: Float = 0
    /// Ngưỡng thực dùng (điểm host): lớn hơn trong hai ngưỡng.
    var effectiveSlop: Float { max(slop, viewSlop * hostPointsPerViewPoint) }
    /// Giữ một ngón đủ `longPressMs` rồi nhả (không kéo) = click phải (cài đặt "nhấn giữ để chuột phải");
    /// tắt thì nhả ra là click trái.
    public var longPressRightClick = true
    /// Cuộn tự nhiên: nội dung đi theo ngón tay; tắt thì đảo chiều.
    public var naturalScroll = true
    /// Chạm 2 lần = mở bàn phím: cú chạm đầu đã click đặt con trỏ gõ, cú thứ hai không gửi gì mà báo UI mở bàn phím.
    public var doubleTapOpensKeyboard = false

    public init(surfaceWidth: Float, surfaceHeight: Float) {
        self.surfaceWidth = surfaceWidth
        self.surfaceHeight = surfaceHeight
    }
}
