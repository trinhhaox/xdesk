import Foundation
import XdeskTransport
import XdeskViewer

extension ViewerController {
    func loadManualHosts() async {
        if let manualStoreError { manualHostError = manualStoreError }
        guard let manualStore else { return }
        manualHosts = await manualStore.hosts
        if let loadError = await manualStore.loadError { manualHostError = loadError }
    }

    /// Lưu máy theo địa chỉ (IP Tailscale 100.x.y.z hoặc tên MagicDNS). Trả `false` khi địa chỉ sai hoặc không lưu được.
    @discardableResult
    func addManualHost(address: String, name: String?) async -> Bool {
        guard let manualStore else { return false }
        do {
            try await manualStore.add(address: address, name: name)
            manualHostError = nil
            manualHosts = await manualStore.hosts
            return true
        } catch {
            manualHostError = error.localizedDescription
            return false
        }
    }

    func removeManualHost(_ host: ManualHost) async {
        guard let manualStore else { return }
        do {
            try await manualStore.remove(address: host.address)
            manualHosts = await manualStore.hosts
        } catch {
            manualHostError = error.localizedDescription
        }
    }

    func connect(toManual host: ManualHost) async {
        guard let target = ViewerTarget.parse(manual: host.address) else { return }
        await connect(to: target, title: host.name)
    }

    /// Sau khi kết nối nhập tay thành công: nhớ IP thực và giờ dùng gần nhất.
    func recordManualConnection(_ session: ViewerSession) async {
        guard let manualStore, session.state == .streaming, case .manual(let host, let port)? = session.connectedTarget else { return }
        do {
            try await manualStore.recordConnection(address: "\(host.lowercased()):\(port)", resolved: session.connectedRemoteAddress)
            manualHosts = await manualStore.hosts
        } catch {
            manualHostError = error.localizedDescription
        }
    }
}
