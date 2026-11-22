import SwiftUI
import XdeskTransport
import XdeskViewer

extension HostListView {
    /// Mac đã ghép: ưu tiên endpoint Bonjour đang thấy, rồi tới địa chỉ lần trước (kiểm tra Tailscale nếu cần).
    func tapPaired(_ row: PairedHostRow, overrideMode: WorkMode? = nil) {
        unreachable = nil
        if let host = model.hosts.first(where: { $0.id == row.id }) {
            model.prepareForConnect(mode: overrideMode)
            connect(.discovered(host))
        } else if let address = row.device.lastAddress, let target = ViewerTarget.parse(manual: address) {
            let runConnect = {
                model.prepareForConnect(mode: overrideMode)
                connect(target)
            }
            if TailscaleSupport.isTailscaleHost(address) {
                let state = TailscaleSupport.detect()
                tailscaleState = state
                if state != .active {
                    pendingTailscale = PendingTailscale(address: address, state: state, proceed: runConnect)
                    return
                }
            }
            runConnect()
        } else {
            model.errorMessage = nil
            unreachable = row
        }
    }

    /// Nút phụ trên dòng máy: mở nhanh chế độ đối ngược (Chuột cảm ứng nếu mặc định xem màn hình, hoặc Chiếu Mac nếu mặc định điều khiển).
    func tapPairedAlternate(_ row: PairedHostRow) {
        let alternate: WorkMode = model.defaultWorkMode.isControlMode ? .mirror : .trackpad
        tapPaired(row, overrideMode: alternate)
    }

    func tapUnpaired(_ host: DiscoveredHost) {
        unreachable = nil
        model.prepareForConnect(mode: .mirror)
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
        let normalized = normalizeManual(saved.address)
        guard let target = ViewerTarget.parse(manual: normalized) else { return }
        connectOrChoose(target, rawAddress: normalized)
    }

    func connectManual() {
        let normalized = normalizeManual(manualText)
        guard let target = ViewerTarget.parse(manual: normalized) else { return }
        connectOrChoose(target, rawAddress: normalized)
    }

    private func connectOrChoose(_ target: ViewerTarget, rawAddress: String) {
        unreachable = nil
        let runConnect: () -> Void = {
            Task {
                if await model.isPaired(address: target) {
                    model.prepareForConnect()
                    await model.connect(to: target)
                } else {
                    model.prepareForConnect(mode: .mirror)
                    choosing = target
                }
            }
        }
        if TailscaleSupport.isTailscaleHost(rawAddress) {
            let state = TailscaleSupport.detect()
            tailscaleState = state
            if state != .active {
                pendingTailscale = PendingTailscale(address: rawAddress, state: state, proceed: runConnect)
                return
            }
        }
        runConnect()
    }

    private func connect(_ target: ViewerTarget) {
        Task { await model.connect(to: target) }
    }
}
