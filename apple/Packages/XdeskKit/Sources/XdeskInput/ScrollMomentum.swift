import Foundation

/// Cuộn quán tính: hất ngón rồi nhả thì trang trôi tiếp và chậm dần, như cuộn trên điện thoại.
/// Đo vận tốc từ các lần cuộn gần nhất; sau khi nhả, mỗi `step` phát thêm một đoạn cuộn tới khi đủ chậm.
struct ScrollMomentum: Sendable {
    /// Nhả ngón quá lâu sau lần cuộn cuối (ngón đã dừng) thì không trôi.
    static let releaseWindowMs: Int64 = 80
    /// Thời hằng giảm tốc (ms): vận tốc còn ~37% sau mỗi khoảng này, gần cảm giác cuộn của iOS.
    static let decayMs: Float = 325
    /// Dưới tốc độ này (điểm host/giây) thì không bắt đầu hoặc dừng trôi.
    static let minSpeed: Float = 60
    /// Chặn tốc độ để một cú hất mạnh không văng quá xa.
    static let maxSpeed: Float = 12_000

    private var velocity = (x: Float(0), y: Float(0))
    private var lastScrollMs: Int64?
    private var lastStepMs: Int64 = 0
    private(set) var isActive = false

    /// Ghi nhận một lần cuộn do ngón tay (điểm host) để ước lượng vận tốc (điểm/giây), làm mượt theo trung bình trượt.
    mutating func track(dx: Float, dy: Float, timeMs: Int64) {
        defer { lastScrollMs = timeMs }
        guard let last = lastScrollMs, timeMs > last else { return }
        let dt = Float(timeMs - last) / 1000
        let blend: Float = 0.6
        velocity.x = blend * (dx / dt) + (1 - blend) * velocity.x
        velocity.y = blend * (dy / dt) + (1 - blend) * velocity.y
    }

    /// Ngón vừa nhả: còn đủ nhanh thì bắt đầu trôi. Trả `true` nếu đang trôi.
    @discardableResult
    mutating func release(timeMs: Int64) -> Bool {
        defer { lastScrollMs = nil }
        guard let last = lastScrollMs, timeMs - last <= Self.releaseWindowMs else { return stop() }
        let speed = (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()
        guard speed >= Self.minSpeed else { return stop() }
        if speed > Self.maxSpeed {
            velocity.x *= Self.maxSpeed / speed
            velocity.y *= Self.maxSpeed / speed
        }
        lastStepMs = timeMs
        isActive = true
        return true
    }

    /// Đoạn cuộn kế tiếp tới `nowMs`; nil khi đã dừng.
    mutating func step(nowMs: Int64) -> (dx: Float, dy: Float)? {
        guard isActive, nowMs > lastStepMs else { return nil }
        let dt = Float(nowMs - lastStepMs)
        lastStepMs = nowMs
        let decay = exp(-dt / Self.decayMs)
        // Quãng đi được trong dt khi vận tốc giảm theo hàm mũ.
        let factor = Self.decayMs / 1000 * (1 - decay)
        let delta = (dx: velocity.x * factor, dy: velocity.y * factor)
        velocity.x *= decay
        velocity.y *= decay
        if (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot() < Self.minSpeed { stop() }
        return delta
    }

    /// Dừng trôi (ngón chạm lại màn hình, đổi cử chỉ).
    @discardableResult
    mutating func stop() -> Bool {
        isActive = false
        velocity = (0, 0)
        lastScrollMs = nil
        return false
    }
}
