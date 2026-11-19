import AppKit
import Observation
import Sparkle

/// Bọc Sparkle 2: kiểm tra cập nhật mỗi 24 giờ (cấu hình trong Info.plist) và khi người dùng bấm menu.
@MainActor
@Observable
final class UpdaterController {
    private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController
    private let feedOverride = FeedOverride()
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: feedOverride, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheckForUpdates = value }
        }
    }

    func checkForUpdates() {
        // App chạy nền (LSUIElement) nên phải đưa lên trước, nếu không hộp thoại cập nhật nằm sau cửa sổ khác.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
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
