import XdeskCrypto
import XdeskTransport
import XdeskViewer

extension StreamViewModel {
    /// Xoá một Mac đã ghép khỏi điện thoại: ngắt phiên nếu đang kết nối máy đó, quên khoá, xoá địa chỉ đã lưu của máy đó.
    /// Mac vẫn giữ thiết bị này trong danh sách của nó cho tới khi người dùng thu hồi trên Mac.
    func forget(_ device: PairedDevice) async {
        let savedAddresses = PairedHostListing.rows(paired: [device], discoveredIds: [], manual: manualHosts).first?.savedAddresses ?? []
        if inStream, isCurrent(device) { await disconnect() }
        await forgetHost(id: device.id)
        for address in savedAddresses {
            guard let saved = manualHosts.first(where: { $0.address == address }) else { continue }
            await removeManualHost(saved)
        }
    }

    private func isCurrent(_ device: PairedDevice) -> Bool {
        switch target {
        case .discovered(let host)?: host.id == device.id
        case .manual(let host, let port)?: "\(host):\(port)" == device.lastAddress
        case nil: false
        }
    }
}
