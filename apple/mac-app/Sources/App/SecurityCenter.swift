import Foundation
import Observation
import os
import XdeskCrypto
import XdeskTransport
import XdeskViewer

/// Chế độ bảo mật của app: luôn `.encrypted`; plaintext chỉ tồn tại ở build Debug và chỉ khi truyền `--plaintext`.
enum AppSecurity {
    static var current: TransportSecurity {
        #if DEBUG
        CommandLine.arguments.contains("--plaintext") ? .devPlaintext : .encrypted
        #else
        .encrypted
        #endif
    }
}

/// Trung tâm bảo mật của app Mac: danh tính, danh sách thiết bị (host + host đã biết), quyết định ghép đôi và cờ cảnh báo
/// cho UI. Phần giao diện (cửa sổ QR, hộp thoại so mã, danh sách thiết bị) chỉ cần đọc các thuộc tính này và gọi các hàm bên dưới.
@MainActor
@Observable
final class SecurityCenter {
    /// Lý do không dựng được danh tính/danh sách (Keychain lỗi, file danh sách hỏng/lạ phiên bản). Khi có lỗi, chế độ mã hoá không chạy.
    private(set) var startupError: String?
    /// Danh sách thiết bị từng bị sửa/hỏng MAC (đã chuyển sang `paired-devices.json.tampered`); UI báo tới khi `acknowledgeIntegrityNotice()`.
    private(set) var integrityNotice = false
    /// Khoá nằm ở login keychain cũ thay vì data-protection keychain: cấu hình ký/entitlement chưa đúng.
    private(set) var keychainWarning = false
    private(set) var identityFingerprint: String?
    private(set) var identityBackend: KeychainBackend?
    /// Viewer được phép kết nối vào máy này.
    private(set) var pairedViewers: [PairedDevice] = []
    /// Host đã ghép (máy này là viewer).
    private(set) var knownHosts: [PairedDevice] = []
    /// QR đang hiển thị (nil = không mở ghép đôi).
    internal(set) var qrURI: PairingURI?
    /// Yêu cầu ghép đôi đang chờ người dùng ở host: hiện hộp thoại rồi gọi `resolvePairing`.
    internal(set) var pendingPairing: PairingRequest?
    /// Bản ghi sự kiện host mới nhất (không chứa bí mật), cho cửa sổ trạng thái/thông báo.
    internal(set) var lastEvent: HostAuthEvent?

    let stores: DeviceSecurityStores?
    let hostAuthenticator: HostAuthenticator?
    /// Khoá công khai của host (báo cho viewer qua `usbHello` để chọn đúng khoá IK).
    var hostPublicKey: [UInt8]? { get async { await hostAuthenticator?.publicKey } }
    let viewerTrust: ViewerTrust?

    @ObservationIgnored let log = Logger(subsystem: "vn.xox.xdesk", category: "security-center")
    @ObservationIgnored var decisionContinuation: CheckedContinuation<PairingDecision, Never>?
    @ObservationIgnored var eventTask: Task<Void, Never>?
    #if DEBUG
    @ObservationIgnored let autoApprovePairing = CommandLine.arguments.contains("--auto-approve-pairing")
    #endif

    init() {
        do {
            let stores = try DeviceSecurityStores.openDefault()
            self.stores = stores
            hostAuthenticator = HostAuthenticator(identity: stores.identity, deviceName: HostIdentity.displayName, store: stores.hostDevices)
            viewerTrust = ViewerTrust(identity: stores.identity, knownHosts: stores.knownHosts)
            identityFingerprint = stores.identity.fingerprint
            identityBackend = stores.identityBackend
            keychainWarning = !stores.usesDataProtectionKeychain
        } catch {
            stores = nil
            hostAuthenticator = nil
            viewerTrust = nil
            startupError = error.localizedDescription
            log.error("không mở được kho bảo mật: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Gắn hook quyết định ghép đôi và bắt đầu nghe sự kiện host. Gọi một lần khi host bật.
    func attach() async {
        guard let hostAuthenticator, eventTask == nil else { return }
        await hostAuthenticator.setPairingDecider { [weak self] request in
            guard let self else { return .reject }
            return await self.decide(request)
        }
        let events = hostAuthenticator.events
        eventTask = Task { [weak self] in
            for await event in events { await self?.handle(event) }
        }
        await refresh()
    }

    func refresh() async {
        guard let stores else { return }
        pairedViewers = await stores.hostDevices.devices
        knownHosts = await stores.knownHosts.devices
        integrityNotice = await stores.integrityNoticePending
    }

    func acknowledgeIntegrityNotice() async {
        await stores?.acknowledgeIntegrityNotice()
        await refresh()
    }

    // MARK: Quản lý thiết bị

    /// Thu hồi: xoá khỏi danh sách và cắt phiên đang chạy của thiết bị (≤ 1 s).
    func revoke(deviceId: String) async {
        do { _ = try await hostAuthenticator?.revokeDevice(id: deviceId) } catch {
            log.error("thu hồi lỗi: \(error.localizedDescription, privacy: .public)")
        }
        await refresh()
    }

    func setPermissions(deviceId: String, _ permissions: DevicePermissions) async {
        do { try await stores?.hostDevices.setPermissions(id: deviceId, permissions) } catch {
            log.error("đổi quyền lỗi: \(error.localizedDescription, privacy: .public)")
        }
        await refresh()
    }

    func forgetHost(deviceId: String) async {
        do { try await stores?.knownHosts.remove(id: deviceId) } catch {
            log.error("quên host lỗi: \(error.localizedDescription, privacy: .public)")
        }
        await refresh()
    }
}
