import CoreGraphics

enum MouseButton: Hashable, Sendable {
    case left, right, other

    init(wire: UInt8) {
        switch wire {
        case 0: self = .left
        case 1: self = .right
        default: self = .other
        }
    }
}

/// Đường tiêm input vào macOS; tách khỏi CGEvent để test bằng đối tượng giả.
protocol EventInjecting: Sendable {
    /// `held` != nil → nút đang giữ nên đây là sự kiện kéo (dragged), không phải di chuột.
    func mouseMove(to point: CGPoint, held: MouseButton?, flags: CGEventFlags)
    func mouseButton(_ button: MouseButton, down: Bool, at point: CGPoint, clickCount: Int, flags: CGEventFlags)
    /// Cuộn theo pixel; `dy` > 0 = nội dung đi xuống.
    func scroll(dx: Int32, dy: Int32, flags: CGEventFlags)
    func key(_ code: CGKeyCode, down: Bool, flags: CGEventFlags)
}
