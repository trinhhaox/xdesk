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
            HStack(spacing: 14) {
                Toggle("Xem", isOn: .constant(true)).disabled(true)
                toggle("Điều khiển", \.input)
                toggle("Clipboard", \.clipboard)
                toggle("Âm thanh", \.audio)
            }
            .toggleStyle(.checkbox).font(.callout)
        }
        .padding(.vertical, 4)
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
