import AppKit
import Observation
import Sparkle

/// Bọc Sparkle 2. Cài đặt (tự kiểm tra, tự tải) lưu bởi chính `SPUUpdater`; lớp này chỉ phản chiếu giá trị để SwiftUI vẽ lại.
@MainActor
@Observable
final class UpdaterController {
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecks = false
    private(set) var automaticallyDownloads = false
    private(set) var allowsAutomaticUpdates = true
    private(set) var lastCheckDate: Date?
    /// Phiên bản Sparkle tìm thấy ở chế độ nền mà chưa hiện hộp thoại (app chạy nền nên nhắc nhẹ qua menu).
    private(set) var pendingVersion: String?

    private let controller: SPUStandardUpdaterController
    private let feedOverride = FeedOverride()
    private let reminders = GentleReminders()
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: feedOverride, userDriverDelegate: reminders)
        reminders.onPendingVersion = { [weak self] version in Task { @MainActor in self?.pendingVersion = version } }
        let updater = controller.updater
        let onChange: @Sendable (SPUUpdater) -> Void = { [weak self] _ in Task { @MainActor in self?.refresh() } }
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.new]) { u, _ in onChange(u) },
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { u, _ in onChange(u) },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { u, _ in onChange(u) },
            updater.observe(\.lastUpdateCheckDate, options: [.new]) { u, _ in onChange(u) },
        ]
        refresh()
    }

    func setAutomaticallyChecks(_ value: Bool) {
        controller.updater.automaticallyChecksForUpdates = value
        refresh()
    }

    func setAutomaticallyDownloads(_ value: Bool) {
        controller.updater.automaticallyDownloadsUpdates = value
        refresh()
    }

    func checkForUpdates() {
        // App chạy nền (LSUIElement) nên phải đưa lên trước, nếu không hộp thoại cập nhật nằm sau cửa sổ khác.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    private func refresh() {
        let updater = controller.updater
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecks = updater.automaticallyChecksForUpdates
        automaticallyDownloads = updater.automaticallyDownloadsUpdates
        allowsAutomaticUpdates = updater.allowsAutomaticUpdates
        lastCheckDate = updater.lastUpdateCheckDate
    }
}

/// Nhắc nhẹ (gentle reminders): app menu bar hầu như không bao giờ ở tiêu điểm nên bản mới tìm thấy lúc nền
/// sẽ không bật cửa sổ chắn việc của người dùng mà chỉ đổi biểu tượng và thêm mục trong menu.
final class GentleReminders: NSObject, SPUStandardUserDriverDelegate {
    var onPendingVersion: (@Sendable (String?) -> Void)?

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        UpdateReminderPolicy.sparkleShouldPresent(inImmediateFocus: immediateFocus)
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate { onPendingVersion?(update.displayVersionString) }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) { onPendingVersion?(nil) }

    func standardUserDriverWillFinishUpdateSession() { onPendingVersion?(nil) }
}

/// Chỉ bản Debug mới đổi được nguồn appcast (biến môi trường XDESK_APPCAST_URL) để thử mà không đụng bản phát hành.
private final class FeedOverride: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["XDESK_APPCAST_URL"]
        #else
        return nil
        #endif
    }
}
