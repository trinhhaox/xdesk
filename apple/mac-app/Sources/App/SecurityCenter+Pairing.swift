import Foundation
import XdeskCrypto
import XdeskTransport

extension SecurityCenter {
    // MARK: QR

    /// Mở ghép đôi bằng QR: trả URI để vẽ mã. Token tự đổi khi đang có phiên và hết hạn sau 2 phút (`qrURI` về nil).
    /// Cửa sổ vẽ QR phải đặt `sharingType = .none` và loại khỏi bộ lọc capture (host không được stream lại chính mã QR).
    @discardableResult
    func startQrPairing(port: UInt16) async -> PairingURI? {
        guard let hostAuthenticator else { return nil }
        var addresses = ["127.0.0.1:\(port)"]
        if let lan = LocalAddress.primaryIPv4() { addresses.insert("\(lan):\(port)", at: 0) }
        do {
            return try await hostAuthenticator.startQrPairing(addresses: addresses)
        } catch {
            log.error("không mở được QR: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func stopQrPairing() async { await hostAuthenticator?.stopQrPairing() }

    // MARK: Quyết định

    /// Người dùng bấm "Cho phép" (QR) / "Khớp" (SAS) → `approve(permissions)`; "Từ chối"/"Không khớp" → `.reject`.
    func resolvePairing(_ decision: PairingDecision) {
        decisionContinuation?.resume(returning: decision)
        decisionContinuation = nil
        pendingPairing = nil
    }

    /// Hook của `HostAuthenticator`: chờ UI trả lời. Yêu cầu thứ hai khi đang có một yêu cầu chờ bị từ chối ngay.
    func decide(_ request: PairingRequest) async -> PairingDecision {
        #if DEBUG
        if autoApprovePairing {
            if case .sas(let code) = request.method {
                print("xdesk-sas-host-code \(code)")
                fflush(stdout)
            }
            return .approve(.default)
        }
        #endif
        guard decisionContinuation == nil else { return .reject }
        pendingPairing = request
        return await withCheckedContinuation { decisionContinuation = $0 }
    }

    func handle(_ event: HostAuthEvent) async {
        lastEvent = event
        switch event {
        case .qrIssued(let uri): qrURI = uri
        case .qrClosed: qrURI = nil
        case .pairingResolved, .sessionOpened, .sessionClosed, .sessionRevoked: await refresh()
        case .pairingPending: break
        }
        if case .pairingResolved = event, pendingPairing != nil { resolvePairing(.reject) }
    }
}
