import SwiftUI
import XdeskTransport
import XdeskViewer

extension HostListView {
    /// Mac đã ghép: ưu tiên endpoint Bonjour đang thấy, rồi tới địa chỉ lần trước; không có đường nào thì báo bằng thẻ lỗi.
    func tapPaired(_ row: PairedHostRow) {
        unreachable = nil
        if let host = model.hosts.first(where: { $0.id == row.id }) {
            connect(.discovered(host))
        } else if let address = row.device.lastAddress, let target = ViewerTarget.parse(manual: address) {
            connect(target)
        } else {
            model.errorMessage = nil
            unreachable = row
        }
    }

    /// Kết nối thẳng vào chế độ Bàn phím & Chuột ảo toàn màn hình.
    func tapPairedTrackpad(_ row: PairedHostRow) {
        model.isTrackpadOnlyMode = true
        tapPaired(row)
    }

    func tapUnpaired(_ host: DiscoveredHost) {
        unreachable = nil
        switch model.hostStates[host.id] {
        case .none, .paired?: connect(.discovered(host))
        case .unknown?: choosing = .discovered(host)
        case .keyChanged(let expected)?: changedKey = KeyChange(host: host, expected: expected)
        }
    }

    private func normalizeManual(_ text: String) -> String {
        OtherConnectionsSection.normalizedAddress(text)
    }

    func connectSaved(_ saved: ManualHost) {
        guard let target = ViewerTarget.parse(manual: normalizeManual(saved.address)) else { return }
        connectOrChoose(target)
    }

    func connectManual() {
        guard let target = ViewerTarget.parse(manual: normalizeManual(manualText)) else { return }
        connectOrChoose(target)
    }

    private func connectOrChoose(_ target: ViewerTarget) {
        unreachable = nil
        Task {
            if await model.isPaired(address: target) { await model.connect(to: target) } else { choosing = target }
        }
    }

    private func connect(_ target: ViewerTarget) {
        Task { await model.connect(to: target) }
    }
}
