import XdeskClipboard
import XdeskTransport
import XdeskViewer

extension StreamViewModel {
    /// Kho máy nhập tay; không mở được thì báo lỗi lên UI.
    private var store: ManualHostStore? {
        switch manualStore {
        case .success(let store): return store
        case .failure(let error):
            manualHostError = error.localizedDescription
            return nil
        }
    }

    func loadManualHosts() async {
        guard let manualStore = store else { return }
        manualHosts = await manualStore.hosts
        if let loadError = await manualStore.loadError { manualHostError = loadError }
    }

    /// Lưu máy theo địa chỉ (IP Tailscale 100.x.y.z hoặc tên MagicDNS). Trả `false` khi địa chỉ sai hoặc không lưu được.
    @discardableResult
    func addManualHost(address: String) async -> Bool {
        guard let manualStore = store else { return false }
        do {
            try await manualStore.add(address: address)
            manualHostError = nil
            manualHosts = await manualStore.hosts
            return true
        } catch {
            manualHostError = error.localizedDescription
            return false
        }
    }

    func removeManualHost(_ host: ManualHost) async {
        guard let manualStore = store else { return }
        do {
            try await manualStore.remove(address: host.address)
            manualHosts = await manualStore.hosts
        } catch {
            manualHostError = error.localizedDescription
        }
    }

    /// Sau khi kết nối nhập tay thành công: nhớ IP thực và giờ dùng gần nhất.
    func recordManualConnection() async {
        guard let manualStore = store, session.state == .streaming, case .manual(let host, let port)? = session.connectedTarget else { return }
        do {
            try await manualStore.recordConnection(address: "\(host.lowercased()):\(port)", resolved: session.connectedRemoteAddress)
            manualHosts = await manualStore.hosts
        } catch {
            manualHostError = error.localizedDescription
        }
    }

    // MARK: Clipboard

    /// Nút "Gửi clipboard sang Mac": đọc UIPasteboard CHỈ khi người dùng bấm (và app đang foreground).
    func sendClipboardToMac() async {
        switch await session.sendClipboard() {
        case .sent(.text): clipboardNotice = "Đã gửi văn bản sang Mac"
        case .sent(.image): clipboardNotice = "Đã gửi ảnh sang Mac"
        case .disabled: clipboardNotice = "Mac chưa cho phép clipboard cho thiết bị này"
        case .nothingToSend: clipboardNotice = "Clipboard trống, quá 10 MB hoặc là mật khẩu (không gửi)"
        case .failed(let reason): clipboardNotice = "Không gửi được: \(reason)"
        }
        try? await Task.sleep(for: .seconds(3))
        clipboardNotice = nil
    }
}
