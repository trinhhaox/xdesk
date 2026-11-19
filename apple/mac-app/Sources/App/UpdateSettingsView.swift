import SwiftUI

/// Cửa sổ "Cập nhật": bật/tắt tự kiểm tra, tự tải và cài, xem phiên bản, lần kiểm tra gần nhất.
struct UpdateSettingsView: View {
    let updater: UpdaterController

    var body: some View {
        Form {
            Section("Tự động") {
                Toggle("Tự động kiểm tra cập nhật", isOn: Binding(get: { updater.automaticallyChecks }, set: updater.setAutomaticallyChecks))
                Toggle("Tự động tải và cài bản mới", isOn: Binding(get: { updater.automaticallyDownloads }, set: updater.setAutomaticallyDownloads))
                    .disabled(!updater.automaticallyChecks || !updater.allowsAutomaticUpdates)
                Text("Xdesk kiểm tra mỗi 24 giờ. Khi tìm thấy bản mới lúc đang chạy nền, biểu tượng trên thanh menu đổi dấu và menu có mục để cài.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Hiện tại") {
                Text(UpdateSettingsText.versionLine(
                    shortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                    build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String))
                Text(UpdateSettingsText.lastCheckLine(updater.lastCheckDate))
                if let version = updater.pendingVersion { Text("Có bản mới \(version)").foregroundStyle(.tint) }
                Button("Kiểm tra cập nhật…") { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}
