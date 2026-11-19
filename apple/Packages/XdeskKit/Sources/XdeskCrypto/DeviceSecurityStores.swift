import Foundation
import os

/// Bộ lưu trữ bảo mật của một thiết bị: danh tính (Keychain) + hai danh sách thiết bị, mỗi danh sách một file và một khoá MAC.
/// - `hostDevices`: viewer được phép kết nối vào máy này (role viewer) — host dùng.
/// - `knownHosts`: host mà máy này đã ghép (role host, kèm địa chỉ gần nhất) — viewer dùng. iOS chỉ dùng cái này.
public struct DeviceSecurityStores: Sendable {
    public static let hostDevicesFile = "paired-devices.json"
    public static let knownHostsFile = "known-hosts.json"
    private static let log = Logger(subsystem: "vn.xox.xdesk", category: "security-stores")

    public let identity: DeviceIdentity
    public let hostDevices: PairedDevicesStore
    public let knownHosts: PairedDevicesStore
    /// Keychain thực sự chứa khoá tĩnh. Bản đã ký đúng phải là `.dataProtection`.
    public let identityBackend: KeychainBackend?
    public let macKeyBackends: [KeychainBackend]

    /// `true` chỉ khi mọi bí mật nằm trong data-protection keychain. `false` → UI nên cảnh báo cấu hình ký/entitlement.
    public var usesDataProtectionKeychain: Bool {
        identityBackend == .dataProtection && macKeyBackends.allSatisfy { $0 == .dataProtection }
    }

    /// Mở (hoặc tạo) danh tính và hai danh sách trong `directory` (mặc định `Application Support/Xdesk`).
    /// Chỉ log tên backend, không log khoá.
    public static func openDefault(directory: URL? = nil, policy: DataProtectionPolicy = .preferred) throws -> DeviceSecurityStores {
        let directory = try directory ?? FilePairedDevicesStorage.defaultURL().deletingLastPathComponent()
        let identityStore = KeychainDeviceIdentityStore(policy: policy)
        let identity = try identityStore.loadOrCreate()
        let hostKey = KeychainPairedDevicesMACKeyStore(service: "vn.xox.xdesk.paired-devices-mac", policy: policy)
        let knownKey = KeychainPairedDevicesMACKeyStore(service: "vn.xox.xdesk.known-hosts-mac", policy: policy)
        let hostDevices = try PairedDevicesStore(
            storage: FilePairedDevicesStorage(url: directory.appendingPathComponent(hostDevicesFile)), macKey: hostKey)
        let knownHosts = try PairedDevicesStore(
            storage: FilePairedDevicesStorage(url: directory.appendingPathComponent(knownHostsFile)), macKey: knownKey)
        let stores = DeviceSecurityStores(
            identity: identity, hostDevices: hostDevices, knownHosts: knownHosts, identityBackend: identityStore.backend,
            macKeyBackends: [hostKey.backend, knownKey.backend].compactMap { $0 })
        log.notice("keychain backend identity=\(String(describing: stores.identityBackend), privacy: .public) dataProtectionOnly=\(stores.usesDataProtectionKeychain, privacy: .public)")
        return stores
    }

    public init(
        identity: DeviceIdentity, hostDevices: PairedDevicesStore, knownHosts: PairedDevicesStore,
        identityBackend: KeychainBackend?, macKeyBackends: [KeychainBackend]
    ) {
        self.identity = identity
        self.hostDevices = hostDevices
        self.knownHosts = knownHosts
        self.identityBackend = identityBackend
        self.macKeyBackends = macKeyBackends
    }

    /// Một trong hai danh sách từng bị sửa/hỏng MAC (UI báo cho tới khi người dùng xác nhận).
    public var integrityNoticePending: Bool {
        get async {
            let host = await hostDevices.integrityNoticePending
            let known = await knownHosts.integrityNoticePending
            return host || known
        }
    }

    public func acknowledgeIntegrityNotice() async {
        await hostDevices.acknowledgeIntegrityNotice()
        await knownHosts.acknowledgeIntegrityNotice()
    }
}
