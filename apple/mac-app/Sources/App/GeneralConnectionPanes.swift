import ServiceManagement
import SwiftUI
import XdeskTransport

/// Tab "Chung": mở khi đăng nhập, âm thanh, co giãn cửa sổ.
struct GeneralSettingsPane: View {
    let host: HostController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var language = AppLanguageChoice.stored()
    @State private var languageChanged = false
    @State private var showUnlockSheet = false
    @State private var password1 = ""
    @State private var password2 = ""
    @State private var unlockError: String?

    var body: some View {
        ScrollView {
            Form {
                Section("Khởi động") {
                    Toggle("Mở Xdesk khi đăng nhập", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                    if let loginError { Text(loginError).font(.footnote).foregroundStyle(.red) }
                }
                Section {
                    Picker("Ngôn ngữ", selection: Binding(get: { language }, set: setLanguage)) {
                        Text("Theo hệ thống").tag(AppLanguageChoice.system)
                        Text(verbatim: "Tiếng Việt").tag(AppLanguageChoice.vietnamese)
                        Text(verbatim: "English").tag(AppLanguageChoice.english)
                    }
                    if languageChanged {
                        Text("Khởi động lại Xdesk để áp dụng ngôn ngữ mới.").font(.footnote).foregroundStyle(.secondary)
                        Button("Mở lại ngay") { AppRelauncher.relaunch() }
                    }
                }
                Section("Âm thanh") {
                    Toggle("Chỉ phát âm thanh trên thiết bị (tắt loa Mac)", isOn: Binding(
                        get: { host.audioOptions.muteLocalOutput }, set: { host.audioOptions.setMuteLocalOutput($0) }))
                }
                Section("Cửa sổ") {
                    Toggle("Tự co giãn cửa sổ ứng dụng cho vừa màn hình", isOn: Binding(get: { host.fitWindows }, set: { host.setFitWindows($0) }))
                    Text("Áp dụng ở chế độ Bản sao khi màn hình thiết bị nhỏ hơn Mac.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Màn hình phụ") {
                    Picker("Vị trí màn hình phụ", selection: Binding(get: { host.extendSide }, set: { host.setExtendSide($0) })) {
                        ForEach(ExtendSide.allCases) { side in
                            Text(side.title).tag(side)
                        }
                    }
                    Text("Chọn phía đặt màn hình mở rộng so với màn hình Mac chính (áp dụng cho kết nối mới hoặc lần cấu hình lại tiếp theo).").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Mở khoá Mac từ xa") {
                    Toggle("Cho phép mở khoá màn hình Mac từ xa", isOn: Binding(
                        get: { host.remoteUnlockEnabled && host.hasRemoteUnlockPassword },
                        set: { next in
                            if next {
                                if host.hasRemoteUnlockPassword {
                                    host.setRemoteUnlockEnabled(true)
                                } else {
                                    password1 = ""
                                    password2 = ""
                                    unlockError = nil
                                    showUnlockSheet = true
                                }
                            } else {
                                host.setRemoteUnlockEnabled(false)
                            }
                        }
                    ))
                    HStack {
                        Button(host.hasRemoteUnlockPassword ? "Đổi mật khẩu…" : "Đặt mật khẩu đăng nhập…") {
                            password1 = ""
                            password2 = ""
                            unlockError = nil
                            showUnlockSheet = true
                        }
                        if host.hasRemoteUnlockPassword {
                            Spacer()
                            Button("Xoá mật khẩu", role: .destructive) { host.clearRemoteUnlockPassword() }
                        }
                    }
                    Text("Mật khẩu chỉ lưu cục bộ trong macOS Keychain (không gửi qua mạng) và chỉ gõ khi Mac đang khoá + bạn đã cấp quyền \"Mở khoá Mac\" cho từng thiết bị ở tab Thiết bị.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: SettingsView.width, height: 500)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
        .sheet(isPresented: $showUnlockSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mật khẩu mở khoá macOS").font(.headline)
                Text("Lưu cục bộ trong Keychain để tự gõ khi bạn xác thực sinh trắc học từ điện thoại.")
                    .font(.footnote).foregroundStyle(.secondary)
                SecureField("Mật khẩu đăng nhập Mac", text: $password1)
                    .textFieldStyle(.roundedBorder)
                SecureField("Nhập lại mật khẩu", text: $password2)
                    .textFieldStyle(.roundedBorder)
                if let unlockError {
                    Text(unlockError).font(.footnote).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Huỷ") { showUnlockSheet = false }
                    Button("Lưu vào Keychain") {
                        guard !password1.isEmpty else { unlockError = "Vui lòng nhập mật khẩu"; return }
                        guard password1 == password2 else { unlockError = "Hai lần nhập mật khẩu chưa khớp"; return }
                        do {
                            try host.saveRemoteUnlockPassword(password1)
                            password1 = ""
                            password2 = ""
                            showUnlockSheet = false
                        } catch {
                            unlockError = error.localizedDescription
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(width: 380)
        }
    }

    private func setLanguage(_ choice: AppLanguageChoice) {
        guard choice != language else { return }
        choice.save()
        language = choice
        languageChanged = true
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = String(localized: "Không đổi được cài đặt khởi động: \(error.localizedDescription)")
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
        guard let address = system.tailscaleAddress else { return String(localized: "Chưa thấy Tailscale trên máy này") }
        return String(localized: "Đang chạy") + " · " + (port.map { EndpointFormat.hostPort(address, $0) } ?? address)
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
                    Text(verbatim: system.lanAddress.map { address in port.map { EndpointFormat.hostPort(address, $0) } ?? address } ?? String(localized: "Chưa có"))
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
