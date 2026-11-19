import XdeskCrypto
import XdeskTransport
import XdeskViewer

extension StreamViewModel {
    var requiresPairing: Bool { AppSecurity.current == .encrypted }

    var ownFingerprint: String? { security?.identity.fingerprint }

    func refreshTrust() async {
        guard let trust, requiresPairing else {
            hostStates = [:]
            return
        }
        var next: [String: ViewerTrust.HostState] = [:]
        for host in hosts { next[host.id] = await trust.state(of: host) }
        hostStates = next
        knownHosts = await trust.knownHosts.devices
    }

    /// Địa chỉ nhập tay đã từng ghép (kết nối lại được)? Chạy không mã hoá thì luôn coi là được.
    func isPaired(address target: ViewerTarget) async -> Bool {
        guard requiresPairing, let trust, case .manual(let host, let port) = target else { return true }
        return await trust.device(address: "\(host):\(port)") != nil
    }

    /// Ghép đôi bằng URI QR đã quét (`xdesk://pair?...`) rồi vào luôn màn hình stream.
    func pair(with uri: PairingURI) async {
        guard let first = uri.addresses.compactMap(ViewerTarget.parse(address:)).first else {
            errorMessage = "Mã QR không có địa chỉ hợp lệ."
            return
        }
        isPairing = true
        await begin(first) { await self.session.pair(with: uri, config: $0) }
        isPairing = false
        pairingFinished()
    }

    /// Ghép đôi bằng mã 6 số: `sasCode` hiện trên màn hình stream tới khi Mac bấm "Khớp".
    func pairWithCode(to target: ViewerTarget) async {
        isPairing = true
        sasCode = nil
        await begin(target) { config in
            await self.session.connect(to: target, config: config, auth: .sas(onCode: { code in
                await MainActor.run { self.sasCode = code }
            }))
        }
        sasCode = nil
        isPairing = false
        pairingFinished()
    }

    /// Rung báo kết quả ghép đôi; bấm Huỷ (không có lỗi) thì không rung.
    private func pairingFinished() {
        if inStream, session.state == .streaming { Haptics.result(success: true) }
        else if errorMessage != nil { Haptics.result(success: false) }
    }

    func forgetHost(id: String) async {
        do { try await security?.knownHosts.remove(id: id) } catch { errorMessage = "Không quên được máy này: \(error.localizedDescription)" }
        await refreshTrust()
    }
}
