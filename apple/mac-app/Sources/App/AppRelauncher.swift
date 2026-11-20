import AppKit

/// Mở lại Xdesk: dùng khi macOS chỉ áp dụng thay đổi (quyền Ghi màn hình, ngôn ngữ) sau khi app khởi động lại.
@MainActor
enum AppRelauncher {
    /// Mở một bản Xdesk mới rồi thoát bản hiện tại.
    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            Task { @MainActor in NSApplication.shared.terminate(nil) }
        }
    }
}
