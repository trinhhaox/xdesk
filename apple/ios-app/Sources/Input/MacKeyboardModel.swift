import Foundation
import Observation
import UIKit
import XdeskInput
import XdeskWire

/// Cầu nối UI ↔ `MacKeyboardController`: nhận chạm xuống/lên, gửi `InputEvent` HID qua `send`
/// (cùng đường `ViewerSession.sendInput` với bàn phím vật lý), chạy bộ lặp phím và phản hồi xúc giác.
@MainActor
@Observable
final class MacKeyboardModel {
    private static let tickInterval: TimeInterval = 0.05

    @ObservationIgnored var send: ([InputEvent]) -> Void = { _ in }
    private(set) var controller = MacKeyboardController()
    /// Lớp `fn` của bố cục gọn: hàng số hiện esc F1–F12. Chỉ là trạng thái giao diện, không gửi sang Mac.
    private(set) var fnLayerOn = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let haptic = UIImpactFeedbackGenerator(style: .light)

    func touchDown(touchId: Int, usage: UInt16) {
        if usage == MacKeyboardLayout.fnLayerUsage {
            haptic.impactOccurred()
            fnLayerOn.toggle()
            return
        }
        guard let key = MacKeyboardLayout.allKeys.first(where: { $0.usage == usage }) else { return }
        haptic.impactOccurred()
        emit(controller.press(touchId: touchId, key: key, nowMs: Self.nowMs))
        startTimerIfNeeded()
    }

    func touchUp(touchId: Int) {
        emit(controller.release(touchId: touchId, nowMs: Self.nowMs))
    }

    /// Rời chế độ / vào nền / ngắt kết nối: nhả hết phím và bổ trợ.
    func releaseAll() {
        stopTimer()
        emit(controller.releaseAll())
    }

    /// Ngắt kết nối phiên: nhả hết và tắt Caps Lock.
    func reset() {
        releaseAll()
        controller.clearCapsLock()
    }

    private func emit(_ events: [InputEvent]) {
        if !events.isEmpty { send(events) }
    }

    private func startTimerIfNeeded() {
        guard controller.isRepeating, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        emit(controller.tick(nowMs: Self.nowMs))
        if !controller.isRepeating { stopTimer() }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private static var nowMs: Int64 { Int64(ProcessInfo.processInfo.systemUptime * 1000) }
}
