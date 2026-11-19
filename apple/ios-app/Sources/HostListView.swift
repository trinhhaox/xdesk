import SwiftUI
import UIKit
import XdeskCrypto
import XdeskTransport
import XdeskViewer
import XdeskWire

/// Danh sách máy Mac trên LAN (Bonjour) + nhập tay `host:port` (cũng dùng cho Tailscale).
struct HostListView: View {
    let model: StreamViewModel
    @AppStorage("xdesk.lastManualHost") private var manualText = ""
    /// Đích chưa ghép đôi đang chờ người dùng chọn cách ghép.
    @State private var choosing: ViewerTarget?
    @State private var changedKey: KeyChange?
    @State private var showScanner = false
    @State private var showSettings = false

    private struct KeyChange: Identifiable {
        let host: DiscoveredHost
        let expected: PairedDevice
        var id: String { host.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.localNetworkDenied { localNetworkGuidance }
                modePicker
                Section("Máy Mac trên mạng") {
                    if model.hosts.isEmpty {
                        Text("Đang tìm… (trên Mac cần bật \"Bắt đầu chia sẻ\")").foregroundStyle(.secondary)
                    }
                    ForEach(model.hosts) { host in
                        Button { tap(host) } label: { hostLabel(host) }
                    }
                }
                if !model.manualHosts.isEmpty {
                    Section("Máy đã lưu (Tailscale / nhập tay)") {
                        ForEach(model.manualHosts) { saved in
                            Button { connectSaved(saved) } label: { savedLabel(saved) }
                                .swipeActions {
                                    Button("Xoá", role: .destructive) { Task { await model.removeManualHost(saved) } }
                                }
                        }
                    }
                }
                Section {
                    TextField("host:port, ví dụ 192.168.1.10:47800 hoặc 100.x.y.z", text: $manualText)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(connectManual)
                    Button("Kết nối", action: connectManual).disabled(ViewerTarget.parse(manual: manualText) == nil)
                    Button("Lưu máy này") { Task { if await model.addManualHost(address: manualText) { manualText = "" } } }
                        .disabled(ManualHostAddress(manualText) == nil)
                } header: {
                    Text("Nhập địa chỉ")
                } footer: {
                    Text("Qua Tailscale: nhập IP 100.x.y.z hoặc tên máy (MagicDNS) của Mac, rồi \"Lưu máy này\". Trên Mac phải bật \"Cho phép kết nối qua Tailscale\".")
                }
                if let message = model.errorMessage ?? model.manualHostError { Section { Text(message).foregroundStyle(.red) } }
            }
            .navigationTitle("Xdesk")
            .refreshable { model.stopBrowsing(); model.startBrowsing() }
            .toolbar {
                Button("Bảo mật", systemImage: "lock.shield") { showSettings = true }
                Button("Tìm lại", systemImage: "arrow.clockwise") { model.stopBrowsing(); model.startBrowsing() }
            }
            .sheet(isPresented: $showScanner) { PairWithMacView(model: model) }
            .sheet(isPresented: $showSettings) { SecuritySettingsView(model: model) }
            .confirmationDialog("Chưa ghép đôi với máy này", isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } }),
                                titleVisibility: .visible, presenting: choosing) { target in
                Button("Quét mã QR trên Mac") { showScanner = true }
                Button("So mã 6 số") { Task { await model.pairWithCode(to: target) } }
            } message: { _ in
                Text("Ghép đôi một lần, những lần sau Xdesk tự kết nối.")
            }
            .alert("Khoá của máy này đã đổi", isPresented: Binding(get: { changedKey != nil }, set: { if !$0 { changedKey = nil } }), presenting: changedKey) { change in
                Button("Quên khoá cũ", role: .destructive) { Task { await model.forgetHost(id: change.expected.id) } }
                Button("Đóng", role: .cancel) {}
            } message: { change in
                Text("\"\(change.host.name)\" có khoá khác lần ghép trước: máy được cài lại hoặc có thiết bị khác đang mạo danh. Xdesk không kết nối. Chỉ chọn \"Quên khoá cũ\" nếu bạn biết máy đó vừa được cài lại.")
            }
            .alert("Mac từ chối kết nối", isPresented: Binding(get: { model.refusedHost != nil }, set: { if !$0 { model.refusedHost = nil } }),
                   presenting: model.refusedHost) { refused in
                Button("Ghép đôi lại") {
                    Task {
                        await model.forgetHost(id: refused.hostId)
                        choosing = refused.target
                    }
                }
                Button("Đóng", role: .cancel) {}
            } message: { _ in
                Text("Máy Mac không còn nhận thiết bị này, thường là do đã bấm \"Thu hồi\" trên Mac. Chọn \"Ghép đôi lại\" để quét mã QR hoặc so mã 6 số.")
            }
        }
        .onAppear {
            model.startBrowsing()
            Task { await model.loadManualHosts() }
        }
        .onDisappear { model.stopBrowsing() }
    }

    private var modePicker: some View {
        @Bindable var model = model
        return Section {
            Picker("Chế độ", selection: $model.screenMode) {
                Text("Mở rộng").tag(ScreenMode.extend)
                Text("Bản sao").tag(ScreenMode.mirror)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Chế độ hiển thị")
        } footer: {
            Text(model.screenMode == .extend
                 ? "Điện thoại là màn hình thứ hai bên phải Mac. Kéo cửa sổ sang để dùng."
                 : "Điện thoại hiện đúng màn hình Mac. Màn hình Mac tự đổi theo kích thước và chiều xoay của điện thoại.")
        }
    }

    private var localNetworkGuidance: some View {
        Section("Chưa có quyền Mạng nội bộ") {
            Text("Xdesk cần quyền Mạng nội bộ để tìm máy Mac. Bật quyền trong Cài đặt, hoặc nhập địa chỉ IP của Mac ở dưới.")
            Button("Mở Cài đặt") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        }
    }

    private func hostLabel(_ host: DiscoveredHost) -> some View {
        HStack {
            Label(host.name, systemImage: "desktopcomputer")
            Spacer()
            if let badge = model.hostStates[host.id]?.badge {
                Text(badge.title).font(.caption.bold()).foregroundStyle(color(badge))
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

    private func tap(_ host: DiscoveredHost) {
        switch model.hostStates[host.id] {
        case .none, .paired?: connect(.discovered(host))
        case .unknown?: choosing = .discovered(host)
        case .keyChanged(let expected)?: changedKey = KeyChange(host: host, expected: expected)
        }
    }

    private func savedLabel(_ saved: ManualHost) -> some View {
        VStack(alignment: .leading) {
            Label(saved.name, systemImage: "network")
            Text(saved.lastAddress.map { "\(saved.address) · IP lần trước \($0)" } ?? saved.address)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func connectSaved(_ saved: ManualHost) {
        guard let target = ViewerTarget.parse(manual: saved.address) else { return }
        Task {
            if await model.isPaired(address: target) { await model.connect(to: target) } else { choosing = target }
        }
    }

    private func connectManual() {
        guard let target = ViewerTarget.parse(manual: manualText) else { return }
        Task {
            if await model.isPaired(address: target) { await model.connect(to: target) } else { choosing = target }
        }
    }

    private func connect(_ target: ViewerTarget) {
        Task { await model.connect(to: target) }
    }
}
