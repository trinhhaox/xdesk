import ServiceManagement
import SwiftUI
import XdeskTransport

/// Tab "Chung": mở khi đăng nhập, âm thanh, co giãn cửa sổ.
struct GeneralSettingsPane: View {
    let host: HostController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Khởi động") {
                Toggle("Mở Xdesk khi đăng nhập", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let loginError { Text(loginError).font(.footnote).foregroundStyle(.red) }
            }
            Section("Âm thanh") {
                Toggle("Chỉ phát âm thanh trên thiết bị (tắt loa Mac)", isOn: Binding(
                    get: { host.audioOptions.muteLocalOutput }, set: { host.audioOptions.setMuteLocalOutput($0) }))
            }
            Section("Cửa sổ") {
                Toggle("Tự co giãn cửa sổ ứng dụng cho vừa màn hình", isOn: Binding(get: { host.fitWindows }, set: { host.setFitWindows($0) }))
                Text("Áp dụng ở chế độ Bản sao khi màn hình thiết bị nhỏ hơn Mac.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsView.width, height: 360)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Không đổi được cài đặt khởi động: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Tab "Kết nối": Tailscale, địa chỉ LAN, thiết bị USB.
struct ConnectionSettingsPane: View {
    let host: HostController
    @State private var system = SystemSnapshot()
    private let ticker = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var port: UInt16? { if case .listening(let port) = host.status { port } else { nil } }

    private var tailscaleStatus: String {
        guard let address = system.tailscaleAddress else { return "Chưa thấy Tailscale trên máy này" }
        return "Đang chạy · " + (port.map { EndpointFormat.hostPort(address, $0) } ?? address)
    }

    var body: some View {
        Form {
            Section("Tailscale") {
                Toggle("Cho phép kết nối qua Tailscale", isOn: Binding(get: { host.allowTailscale }, set: { host.setAllowTailscale($0) }))
                LabeledContent("Trạng thái") {
                    Text(verbatim: tailscaleStatus).textSelection(.enabled)
                }
            }
            Section("Mạng nội bộ (LAN)") {
                LabeledContent("Địa chỉ nhập trên điện thoại") {
                    Text(verbatim: system.lanAddress.map { address in port.map { EndpointFormat.hostPort(address, $0) } ?? address } ?? "Chưa có")
                        .textSelection(.enabled)
                }
            }
            Section("Cáp USB") {
                if host.usb.devices.isEmpty {
                    Text("Chưa cắm iPhone/iPad. Cắm cáp và mở Xdesk trên thiết bị.").foregroundStyle(.secondary)
                }
                ForEach(host.usb.devices) { device in
                    LabeledContent("Thiết bị …\(device.shortSerial)") {
                        Button("Phát qua USB") { Task { await host.connectUsb(to: device) } }.disabled(!host.isHosting)
                    }
                }
                if let message = host.usbMessage { Text("USB: \(message)").font(.footnote).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsView.width, height: 440)
        .onAppear { system = SystemSnapshot() }
        .onReceive(ticker) { _ in system = SystemSnapshot() }
    }
}
