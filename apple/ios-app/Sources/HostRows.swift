import SwiftUI
import XdeskTransport
import XdeskViewer


private struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
    }
}

/// Mac đã ghép: tên, trạng thái mạng ("Sẵn sàng" / "Qua địa chỉ …" / "Không thấy trên mạng") và nhãn "Đã ghép".
struct PairedHostRowView: View {
    let row: PairedHostRow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.title3)
                .foregroundStyle(row.status == .offline ? Color.secondary : BrandPalette.primary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.device.name).foregroundStyle(.primary)
                Text(row.status.text).font(.subheadline).foregroundStyle(row.status == .ready ? BrandPalette.accent : Color.secondary)
            }
            Spacer(minLength: 8)
            Text(HostBadge.paired.title).font(.caption.bold()).foregroundStyle(BrandPalette.accent)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Mac thấy trên LAN nhưng chưa ghép (hoặc khoá đã đổi).
struct DiscoveredHostRowView: View {
    let host: DiscoveredHost
    let badge: HostBadge

    var body: some View {
        HStack {
            Label(host.name, systemImage: "desktopcomputer")
            Spacer(minLength: 8)
            Text(badge.title).font(.caption.bold()).foregroundStyle(badge == .keyChanged ? BrandPalette.danger : BrandPalette.warning)
            Chevron()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Máy nhập tay / Tailscale chưa gắn với máy đã ghép nào.
struct SavedHostRowView: View {
    let saved: ManualHost

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Label(saved.name, systemImage: "network")
                Text(saved.lastAddress.map { "\(saved.address) · IP lần trước \($0)" } ?? saved.address)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Chevron()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
