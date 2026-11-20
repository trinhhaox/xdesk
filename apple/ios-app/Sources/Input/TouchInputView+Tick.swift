import UIKit
import XdeskInput

extension TouchInputView {
    /// Ngưỡng chạm theo ngón tay: số điểm Mac ứng với một điểm màn hình ở cỡ video đang hiện (kể cả zoom).
    func updateTouchScale() {
        guard let mapper = mapper(), mapper.width > 0 else { return }
        engine?.setHostPointsPerViewPoint(Float(surfacePoints.width) / (mapper.width * viewport.zoom))
    }

    // MARK: Tick 50 ms (nhấn giữ, cuộn quán tính sau khi nhả)

    func updateTimer() {
        if touchIds.isEmpty, engine?.needsTick != true {
            tickTimer?.invalidate()
            tickTimer = nil
        } else if tickTimer == nil {
            tickTimer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
    }

    private func tick() {
        guard var current = engine else { return }
        let wasHolding = current.isHolding
        let events = current.tick(nowMs: Self.nowMs)
        engine = current
        session.sendInput(events)
        // Rung nhẹ khi nhấn giữ đủ lâu: báo người dùng có thể kéo thả, hoặc nhả ra để click phải.
        if !wasHolding, current.isHolding { Haptics.light() }
        updateTimer()
    }

    static var nowMs: Int64 { Int64(ProcessInfo.processInfo.systemUptime * 1000) }
    static func ms(_ touch: UITouch) -> Int64 { Int64(touch.timestamp * 1000) }
}
