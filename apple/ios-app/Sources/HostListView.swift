import SwiftUI
import UIKit
import XdeskTransport
import XdeskViewer
import XdeskWire

/// Danh sách máy Mac trên LAN (Bonjour) + nhập tay `host:port` (cũng dùng cho Tailscale).
struct HostListView: View {
    let model: StreamViewModel
    @AppStorage("xdesk.lastManualHost") private var manualText = ""

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
                        Button { connect(.discovered(host)) } label: { Label(host.name, systemImage: "desktopcomputer") }
                    }
                }
                Section("Nhập địa chỉ") {
                    TextField("host:port, ví dụ 192.168.1.10:47800", text: $manualText)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(connectManual)
                    Button("Kết nối", action: connectManual).disabled(ViewerTarget.parse(manual: manualText) == nil)
                }
                if let message = model.errorMessage { Section { Text(message).foregroundStyle(.red) } }
            }
            .navigationTitle("Xdesk")
            .refreshable { model.stopBrowsing(); model.startBrowsing() }
            .toolbar {
                Button("Tìm lại", systemImage: "arrow.clockwise") { model.stopBrowsing(); model.startBrowsing() }
            }
        }
        .onAppear { model.startBrowsing() }
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

    private func connectManual() {
        guard let target = ViewerTarget.parse(manual: manualText) else { return }
        connect(target)
    }

    private func connect(_ target: ViewerTarget) {
        Task { await model.connect(to: target) }
    }
}
