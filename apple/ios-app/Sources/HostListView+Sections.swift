import SwiftUI
import UIKit
import XdeskTransport
import XdeskViewer

extension HostListView {
    /// "Máy Mac của bạn": mọi Mac đã ghép, kể cả khi không thấy trên mạng.
    var pairedSection: some View {
        Section("Máy Mac của bạn") {
            ForEach(pairedRows) { row in
                HStack(spacing: 4) {
                    Button { tapPaired(row) } label: { PairedHostRowView(row: row) }
                        .buttonStyle(.plain)
                    // Nút "…" hiện rõ để xoá máy: vuốt/nhấn giữ khó phát hiện.
                    Menu {
                        Button("Kết nối", systemImage: "play.display") { tapPaired(row) }
                        Button("Xoá máy này", systemImage: "trash", role: .destructive) { forgetting = row.device }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Tuỳ chọn cho \(row.device.name)")
                }
                .swipeActions { Button("Xoá", role: .destructive) { forgetting = row.device } }
                .contextMenu { Button("Xoá máy này", systemImage: "trash", role: .destructive) { forgetting = row.device } }
            }
        }
    }

    /// "Máy Mac khác trên mạng": thấy trên LAN nhưng chưa ghép (hoặc khoá đã đổi).
    @ViewBuilder var unpairedSection: some View {
        let paired = Set(pairedRows.map(\.id))
        let others = model.hosts.filter { !paired.contains($0.id) }
        if !others.isEmpty {
            Section("Máy Mac khác trên mạng") {
                ForEach(others) { host in
                    Button { tapUnpaired(host) } label: {
                        DiscoveredHostRowView(host: host, badge: model.hostStates[host.id]?.badge ?? .unpaired)
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    /// Máy nhập tay / Tailscale chưa gắn với Mac đã ghép nào (cái đã gắn hiện ở "Máy Mac của bạn").
    @ViewBuilder var savedSection: some View {
        let saved = PairedHostListing.unmergedManual(model.manualHosts, rows: pairedRows)
        if !saved.isEmpty {
            Section("Máy đã lưu (Tailscale / nhập tay)") {
                ForEach(saved) { entry in
                    Button { connectSaved(entry) } label: { SavedHostRowView(saved: entry) }
                        .foregroundStyle(.primary)
                        .swipeActions {
                            Button("Xoá", role: .destructive) { Task { await model.removeManualHost(entry) } }
                        }
                }
            }
        }
    }

    var currentFailure: ConnectionFailure? {
        if let unreachable {
            return ConnectionFailure(
                title: "\"\(unreachable.device.name)\" không thấy trên mạng.",
                hint: "Mở Xdesk trên Mac và bật \"Bắt đầu chia sẻ\", cùng Wi-Fi với điện thoại. Qua Tailscale: nhập địa chỉ ở \"Cách kết nối khác\".",
                detail: nil, symbol: "wifi.exclamationmark", action: .retry)
        }
        return model.errorMessage.map { ConnectionFailure.make(message: $0, hostName: model.connectingName) }
    }

    func errorSection(_ failure: ConnectionFailure) -> some View {
        Section {
            ConnectionErrorCard(failure: failure) {
                if let unreachable { tapPaired(unreachable); return }
                switch failure.action {
                case .retry: Task { await model.retryLast() }
                case .pairAgain: choosing = model.target
                }
            } onDismiss: {
                if unreachable != nil { unreachable = nil } else { model.errorMessage = nil }
            }
        }
    }

    var localNetworkGuidance: some View {
        Section("Chưa có quyền Mạng nội bộ") {
            Text("Xdesk cần quyền Mạng nội bộ để tìm máy Mac. Bật quyền trong Cài đặt, hoặc nhập địa chỉ IP của Mac ở dưới.")
            Button("Mở Cài đặt") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        }
    }
}
