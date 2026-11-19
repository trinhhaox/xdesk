import SwiftUI
import XdeskCrypto
import XdeskTransport
import XdeskViewer

/// Cửa sổ chọn host: danh sách Bonjour (kèm trạng thái ghép đôi) + nhập tay `host:port`.
struct ViewerBrowserView: View {
    @Bindable var controller: ViewerController
    @State private var manualText = ""
    @State private var forgetting: PairedDevice?

    var body: some View {
        Form {
            Section("Máy tìm thấy trên mạng") {
                if controller.hosts.isEmpty {
                    Text("Đang tìm… (host cần bật \"Bắt đầu chia sẻ\")").foregroundStyle(.secondary)
                }
                ForEach(controller.hosts) { host in
                    HostRow(host: host, state: controller.hostStates[host.id], busy: controller.isConnecting,
                            connect: { connect(.discovered(host), title: host.name) },
                            pair: { pair(.discovered(host), title: host.name) },
                            forget: { forgetting = $0 })
                }
            }
            Section("Nhập địa chỉ") {
                TextField("host:port, ví dụ 127.0.0.1:47800", text: $manualText)
                    .onSubmit(connectManual)
                HStack {
                    Button("Kết nối", action: connectManual)
                    if controller.requiresPairing {
                        Button("Ghép đôi bằng mã 6 số") { if let target = manualTarget { pair(target, title: manualText) } }
                    }
                }
                .disabled(manualTarget == nil || controller.isConnecting)
            }
            Section("Tuỳ chọn") {
                Toggle("Retina (HiDPI 2×, 3840×2400)", isOn: $controller.options.retina)
                Toggle("Mở toàn màn hình", isOn: $controller.options.fullScreen)
            }
            if let code = controller.sasCode { SasCodePanel(code: code) }
            else if controller.isConnecting { ProgressView("Đang kết nối…") }
            if let message = controller.errorMessage { Text(message).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 520)
        .onAppear { controller.startBrowsing() }
        .onDisappear { controller.stopBrowsing() }
        .confirmationDialog(
            "Quên khoá cũ của \"\(forgetting?.name ?? "")\"?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }),
            presenting: forgetting
        ) { device in
            Button("Quên khoá cũ", role: .destructive) { Task { await controller.forgetKnownHost(id: device.id) } }
        } message: { _ in
            Text("Chỉ làm việc này nếu bạn biết máy kia vừa được cài lại. Sau đó bạn phải ghép đôi lại bằng mã 6 số.")
        }
    }

    private var manualTarget: ViewerTarget? { ViewerTarget.parse(manual: manualText) }

    private func connectManual() {
        guard let target = manualTarget else { return }
        connect(target, title: manualText)
    }

    private func connect(_ target: ViewerTarget, title: String) {
        Task { await controller.connect(to: target, title: title) }
    }

    private func pair(_ target: ViewerTarget, title: String) {
        Task { await controller.pairWithCode(to: target, title: title) }
    }
}

private struct HostRow: View {
    let host: DiscoveredHost
    let state: ViewerTrust.HostState?
    let busy: Bool
    let connect: () -> Void
    let pair: () -> Void
    let forget: (PairedDevice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(host.name, systemImage: "desktopcomputer")
                Spacer()
                if let badge = state?.badge { Text(badge.title).font(.caption.bold()).foregroundStyle(color(badge)) }
            }
            switch state {
            case .none, .paired?: Button("Kết nối", action: connect).disabled(busy)
            case .unknown?: Button("Ghép đôi bằng mã 6 số", action: pair).disabled(busy)
            case .keyChanged(let expected)?:
                Label("Khoá của máy này đã đổi: máy được cài lại hoặc có thiết bị khác đang mạo danh. Không kết nối.", systemImage: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true)
                Button("Quên khoá cũ…", role: .destructive) { forget(expected) }
            }
        }
    }

    private func color(_ badge: HostBadge) -> Color {
        switch badge {
        case .paired: BrandPalette.accent
        case .unpaired: BrandPalette.warning
        case .keyChanged: .red
        }
    }
}

private struct SasCodePanel: View {
    let code: String

    var body: some View {
        VStack(spacing: 6) {
            Text(code).font(.system(size: 40, weight: .bold, design: .monospaced)).foregroundStyle(BrandPalette.primary)
            Text("Trên Mac kia, kiểm tra cùng mã này rồi bấm \"Khớp, cho phép\". Đang chờ xác nhận…").font(.callout).multilineTextAlignment(.center)
            ProgressView()
        }
        .frame(maxWidth: .infinity)
    }
}
