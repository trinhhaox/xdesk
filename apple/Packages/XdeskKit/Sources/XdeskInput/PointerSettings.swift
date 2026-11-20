/// Cách chạm điều khiển con trỏ Mac.
public enum PointerMode: String, Sendable, CaseIterable, Equatable {
    /// Chạm đâu click đó (màn hình cảm ứng).
    case direct
    /// Một ngón trượt như trackpad, con trỏ di chuyển tương đối.
    case trackpad
}

/// Cài đặt con trỏ, lưu theo app; cả hai viewer (iOS, Android) dùng cùng giá trị mặc định.
public struct PointerSettings: Sendable, Equatable {
    public static let speedRange: ClosedRange<Float> = 0.5...2.5

    public var mode: PointerMode
    /// Hệ số tốc độ con trỏ ở chế độ trackpad.
    public var speed: Float { didSet { speed = Self.clampedSpeed(speed) } }
    /// Cuộn tự nhiên: nội dung đi theo ngón tay.
    public var naturalScroll: Bool
    /// Nhấn giữ một ngón = click phải.
    public var longPressRightClick: Bool
    /// Chế độ chạm trực tiếp: chạm 2 lần vào chỗ cần gõ = đặt con trỏ ở đó và mở bàn phím (thay cho double-click).
    public var doubleTapOpensKeyboard: Bool

    public init(
        mode: PointerMode = .direct, speed: Float = 1, naturalScroll: Bool = true, longPressRightClick: Bool = true,
        doubleTapOpensKeyboard: Bool = true
    ) {
        self.mode = mode
        self.speed = Self.clampedSpeed(speed)
        self.naturalScroll = naturalScroll
        self.longPressRightClick = longPressRightClick
        self.doubleTapOpensKeyboard = doubleTapOpensKeyboard
    }

    /// Giá trị không hữu hạn (file cài đặt hỏng) quay về 1.
    public static func clampedSpeed(_ value: Float) -> Float {
        value.isFinite ? min(speedRange.upperBound, max(speedRange.lowerBound, value)) : 1
    }
}

/// Đường cong gia tốc của trackpad: trượt chậm thì con trỏ đi chậm để canh chính xác, vuốt nhanh thì đi xa.
public enum PointerAcceleration {
    public static let baseGain: Float = 0.5
    public static let slope: Float = 1.5
    public static let maxGain: Float = 3

    /// `velocity` tính bằng chiều rộng màn hình host mỗi giây (ngón vuốt hết khung trong 1 s = 1).
    public static func gain(velocity: Float, speed: Float) -> Float {
        let v = velocity.isFinite ? max(0, velocity) : 0
        return min(maxGain, baseGain + slope * v) * PointerSettings.clampedSpeed(speed)
    }
}
