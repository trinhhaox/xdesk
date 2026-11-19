import XdeskCrypto
import XdeskTransport

/// Danh tính viewer + danh sách host đã biết (cùng kiểu `PairedDevicesStore`, role host).
public struct ViewerTrust: Sendable {
    public enum HostState: Sendable, Equatable {
        /// Fingerprint Bonjour khớp một host đã ghép → kết nối lại bằng IK.
        case paired(PairedDevice)
        case unknown
        /// Cùng tên Bonjour với host đã ghép nhưng fingerprint khác: host cài lại hoặc kẻ mạo danh → cảnh báo, không kết nối.
        case keyChanged(expected: PairedDevice)
    }

    public let identity: DeviceIdentity
    public let knownHosts: PairedDevicesStore

    public init(identity: DeviceIdentity, knownHosts: PairedDevicesStore) {
        self.identity = identity
        self.knownHosts = knownHosts
    }

    public func state(of host: DiscoveredHost) async -> HostState {
        let known = await knownHosts.devices.filter { $0.role == .host }
        if let match = known.first(where: { $0.id == host.id }) { return .paired(match) }
        if let sameName = known.first(where: { $0.name == host.name }) { return .keyChanged(expected: sameName) }
        return .unknown
    }

    /// Host đã ghép từng kết nối thành công tại `host:port` (dùng khi nhập địa chỉ tay).
    public func device(address: String) async -> PairedDevice? {
        await knownHosts.devices.first { $0.role == .host && $0.lastAddress == address }
    }
}

/// Cách viewer xác thực ở lần `connect` này.
public enum ViewerAuth: Sendable {
    /// Host đã ghép → IK; chưa ghép → lỗi `pairingRequired`; khoá đổi → `hostKeyMismatch`.
    case automatic
    /// Quét QR (XXpsk3). Dùng `ViewerSession.pair(with:config:)`.
    case qr(PairingURI)
    /// So mã 6 số: `onCode` nhận mã hiển thị trong lúc chờ host bấm "Khớp".
    case sas(onCode: @Sendable (String) async -> Void)
}
