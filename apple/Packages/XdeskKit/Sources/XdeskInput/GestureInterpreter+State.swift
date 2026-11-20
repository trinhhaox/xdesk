/// Trạng thái mà UI đọc (rung, bàn phím, tick) và tham số đổi được giữa chừng của `GestureInterpreter`.
extension GestureInterpreter {
    /// Đang giữ một ngón đủ lâu (sẵn sàng kéo thả / click phải): UI rung nhẹ khi trạng thái này bật lên.
    public var isHolding: Bool { if case .held = mode { true } else { false } }
    /// Còn việc cần `tick` (chờ nhấn giữ hoặc đang cuộn quán tính) dù không còn ngón nào trên màn hình.
    public var needsTick: Bool { momentum.isActive || !touches.isEmpty }

    /// Vừa chạm 2 lần để gõ (`GestureConfig.doubleTapOpensKeyboard`): UI mở bàn phím. Đọc xong thì xoá.
    public mutating func takeKeyboardRequest() -> Bool {
        defer { keyboardRequested = false }
        return keyboardRequested
    }

    /// Cập nhật tỉ lệ điểm host / điểm màn hình (đổi zoom, xoay máy) mà không mất trạng thái cử chỉ.
    public mutating func setHostPointsPerViewPoint(_ scale: Float) { config.hostPointsPerViewPoint = scale }
}
