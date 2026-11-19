import SwiftUI

/// Biểu tượng thanh menu: giữ `display.2`; có bản mới thì đổi sang dấu cập nhật nhẹ; đang chia sẻ cho viewer thì dùng biến thể đặc.
struct MenuBarIcon: View {
    let host: HostController
    let updater: UpdaterController

    var body: some View {
        if updater.pendingVersion != nil {
            Image(systemName: "arrow.down.circle.fill").accessibilityLabel("Xdesk, có bản cập nhật")
        } else if host.activeViewerCount > 0 {
            Image(systemName: "display.2").symbolVariant(.fill).accessibilityLabel("Xdesk, đang chia sẻ")
        } else {
            Image(systemName: "display.2").accessibilityLabel("Xdesk")
        }
    }
}
