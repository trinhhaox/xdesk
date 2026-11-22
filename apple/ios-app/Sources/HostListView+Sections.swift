import SwiftUI
import UIKit
import XdeskTransport
import XdeskViewer

extension HostListView {
    /// Cảnh báo + nút 1 chạm bật/cài Tailscale khi danh sách có máy kết nối qua tailnet nhưng Tailscale chưa hoạt động.
    @ViewBuilder var tailscaleBanner: some View {
        let pairedNeeds = pairedRows.contains { row in
            row.status != .ready && (
                row.device.lastAddress.map(TailscaleSupport.isTailscaleHost) == true ||
                row.savedAddresses.contains(where: TailscaleSupport.isTailscaleHost)
            )
        }
        let savedNeeds = PairedHostListing.unmergedManual(model.manualHosts, rows: pairedRows)
            .contains { TailscaleSupport.isTailscaleHost($0.address) }
        let manualNeeds = TailscaleSupport.isTailscaleHost(manualText)
        if tailscaleState != .active && (pairedNeeds || savedNeeds || manualNeeds) {
            let installed = tailscaleState == .installedInactive
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "network.badge.shield.half.filled")
                            .font(.title3)
                            .foregroundStyle(BrandPalette.warning)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(installed ? "Tailscale đang tắt" : "Chưa cài đặt Tailscale")
                                .font(.headline)
                            Text(
                                installed
                                    ? "Bật Tailscale để kết nối từ xa tới máy Mac qua mạng Tailscale."
                                    : "Cài ứng dụng Tailscale để kết nối máy Mac từ xa ngoài mạng Wi-Fi."
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        if installed { TailscaleSupport.openApp() } else { TailscaleSupport.openInstall() }
                    } label: {
                        Text(installed ? "Mở Tailscale" : "Cài đặt Tailscale")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrandPalette.primaryFill)
                    .buttonBorderShape(.capsule)
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// "Máy Mac của bạn": mọi Mac đã ghép, kể cả khi không thấy trên mạng.
    var pairedSection: some View {
        let defaultIsControl = model.defaultWorkMode.isControlMode
        return Section("Máy Mac của bạn") {
            ForEach(pairedRows) { row in
                HStack(spacing: 4) {
                    Button {
                        tapPaired(row)
                    } label: { PairedHostRowView(row: row) }
                        .buttonStyle(.plain)
                    Button {
                        tapPairedAlternate(row)
                    } label: {
                        Image(systemName: defaultIsControl ? "macbook" : "computermouse.fill")
                            .font(.title3)
                            .foregroundStyle(BrandPalette.primary)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(defaultIsControl ? "Chiếu màn hình Mac cho \(row.device.name)" : "Chuột cảm ứng cho \(row.device.name)")
                    // Nút "…" hiện rõ để xoá máy: vuốt/nhấn giữ khó phát hiện.
                    Menu {
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
                if let unreachable {
                    tapPaired(unreachable)
                    return
                }
                switch failure.action {
                case .retry:
                    model.prepareForConnect()
                    Task { await model.retryLast() }
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
