import SwiftUI
import XdeskCrypto

/// Một viewer đã ghép: tên, dấu vân tay, lần cuối kết nối, công tắc quyền, nút thu hồi.
struct PairedViewerRow: View {
    let device: PairedDevice
    let security: SecurityCenter
    let onRevoke: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name).font(.headline)
                    Text(device.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    lastSeen
                }
                Spacer()
                Button("Thu hồi", role: .destructive, action: onRevoke)
            }
            HStack(spacing: 12) {
                Toggle("Xem", isOn: .constant(true)).disabled(true)
                toggle("Điều khiển", \.input)
                toggle("Clipboard", \.clipboard)
                toggle("Âm thanh", \.audio)
                toggle("Gửi/nhận tệp", \.fileTransfer)
                toggle("Mở khoá Mac", \.unlock)
            }
            .toggleStyle(.checkbox).font(.callout)
            if device.permissions.unlock { unlockKeyStatus }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var unlockKeyStatus: some View {
        HStack(spacing: 8) {
            if let key = device.unlockKey {
                Text("Khoá Face ID/vân tay: \(UnlockKeyFormat.fingerprint(of: key)) (so với Cài đặt › Bảo mật trên điện thoại)")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                Button("Đặt lại khoá") { Task { await security.resetUnlockKey(deviceId: device.id) } }
                    .controlSize(.small)
            } else if let until = security.unlockEnrollmentUntil[device.id], until > Date() {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, Int(until.timeIntervalSince(context.date)))
                    Label(left > 0
                          ? "Đang chờ điện thoại đăng ký khoá — bấm \"Mở khoá Mac\" trên điện thoại (còn \(left / 60):\(String(format: "%02d", left % 60)))"
                          : "Hết 5 phút mà điện thoại chưa đăng ký — bấm Đặt lại khoá lần nữa",
                          systemImage: left > 0 ? "hourglass" : "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(left > 0 ? Color.accentColor : .orange)
                }
                Button("Đặt lại khoá") { Task { await security.resetUnlockKey(deviceId: device.id) } }
                    .controlSize(.small)
            } else {
                Text("Chưa đăng ký khoá — bấm Đặt lại khoá rồi mở khoá từ điện thoại trong 5 phút")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Đặt lại khoá") { Task { await security.resetUnlockKey(deviceId: device.id) } }
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder private var lastSeen: some View {
        if let seen = device.lastSeen {
            Text("Kết nối lần cuối: \(seen, format: .relative(presentation: .named))").font(.caption).foregroundStyle(.secondary)
        } else {
            Text("Chưa kết nối lần nào").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func toggle(_ title: LocalizedStringKey, _ key: WritableKeyPath<DevicePermissions, Bool>) -> some View {
        Toggle(title, isOn: Binding(
            get: { device.permissions[keyPath: key] },
            set: { value in
                var next = device.permissions
                next[keyPath: key] = value
                Task { await security.setPermissions(deviceId: device.id, next) }
            }))
    }
}
