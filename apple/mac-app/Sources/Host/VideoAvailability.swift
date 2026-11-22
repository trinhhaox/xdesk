import AppKit
import Foundation

/// Quyết định có giữ phiên khi không có hình hay không: Mac tắt màn hình/khoá thì capture và màn hình ảo tạm thời bất khả dụng,
/// nhưng kênh điều khiển phải sống để điện thoại còn gửi `system.unlock`.
enum VideoAvailability {
    static func isSleepingOrLocked(_ state: LockScreenState) -> Bool { state.locked || !state.displayAwake }

    /// `true` = lỗi do Mac ngủ/khoá (giữ phiên ở trạng thái không có hình); `false` = lỗi thật (kết thúc phiên như trước).
    /// Lỗi quyền Ghi màn hình luôn là lỗi thật (khi quyền thực sự chưa cấp). `grace` > 0: SCStream báo dừng có thể đến trước khi cờ ngủ/khoá
    /// của hệ thống kịp đổi nên đợi tối đa `grace` để thấy trạng thái đó.
    static func keepsSession(
        after error: Error?,
        probe: @Sendable () -> LockScreenState,
        screenRecordingGranted: @Sendable () -> Bool = { PermissionsCheck.hasScreenRecording },
        grace: Duration = .zero,
        interval: Duration = .milliseconds(150),
        sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) async -> Bool {
        if let capture = error as? CaptureError, capture == .permissionDenied, !screenRecordingGranted() { return false }
        var elapsed: Duration = .zero
        while true {
            if isSleepingOrLocked(probe()) { return true }
            if elapsed >= grace { return false }
            await sleep(interval)
            elapsed += interval
        }
    }
}

/// Khi nào thử khởi động lại video: tín hiệu hệ thống (thức dậy/mở khoá) thì thử ngay khi màn hình sáng; nhịp poll dự phòng chỉ thử khi
/// màn hình sáng và đã mở khoá (tránh tạo/huỷ màn hình ảo liên tục lúc đang ở màn hình khoá).
enum VideoRetryPolicy {
    enum Trigger: Sendable, Equatable { case signal, poll }

    static func shouldRetry(_ trigger: Trigger, state: LockScreenState) -> Bool {
        switch trigger {
        case .signal: state.displayAwake
        case .poll: state.displayAwake && !state.locked
        }
    }
}

/// Vòng thử lại: mỗi tín hiệu hoặc nhịp poll gọi `attempt`; dừng khi `attempt` trả `true` hoặc task bị huỷ.
enum VideoRetryLoop {
    static func run(
        signals: AsyncStream<Void>, poll: Duration,
        attempt: @escaping @Sendable (VideoRetryPolicy.Trigger) async -> Bool
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in signals {
                    if await attempt(.signal) { return }
                }
            }
            group.addTask {
                while !Task.isCancelled {
                    try? await Task.sleep(for: poll)
                    if Task.isCancelled { return }
                    if await attempt(.poll) { return }
                }
            }
            await group.next()
            group.cancelAll()
        }
    }
}

/// Tín hiệu "màn hình có thể capture được lại": màn hình thức dậy, phiên người dùng active, Mac mở khoá.
enum ScreenWakeSignals {
    private final class Tokens: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(NotificationCenter, NSObjectProtocol)] = []
        func add(_ center: NotificationCenter, _ token: NSObjectProtocol) { lock.withLock { items.append((center, token)) } }
        func removeAll() { lock.withLock { items.forEach { $0.0.removeObserver($0.1) }; items.removeAll() } }
    }

    static func stream() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let tokens = Tokens()
            let workspace = NSWorkspace.shared.notificationCenter
            let distributed = DistributedNotificationCenter.default()
            let sources: [(NotificationCenter, Notification.Name)] = [
                (workspace, NSWorkspace.screensDidWakeNotification),
                (workspace, NSWorkspace.sessionDidBecomeActiveNotification),
                (distributed, Notification.Name("com.apple.screenIsUnlocked")),
            ]
            for (center, name) in sources {
                tokens.add(center, center.addObserver(forName: name, object: nil, queue: nil) { _ in continuation.yield() })
            }
            continuation.onTermination = { _ in tokens.removeAll() }
        }
    }
}
