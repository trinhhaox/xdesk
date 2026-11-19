import XdeskCrypto

/// Yêu cầu ghép đôi đang chờ người dùng ở host quyết định.
public struct PairingRequest: Sendable, Equatable {
    public enum Method: Sendable, Equatable {
        /// Viewer quét QR (token đúng) — host vẫn phải xác nhận.
        case qr
        /// So mã 6 số: `code` dạng "NNN NNN", hiển thị song song với màn hình viewer.
        case sas(code: String)
    }

    public let method: Method
    public let deviceName: String
    public let deviceId: String
    public let publicKey: [UInt8]
}

public enum PairingDecision: Sendable, Equatable {
    case approve(DevicePermissions)
    case reject
}

/// Hook cho UI host: hiện hộp thoại (QR: "Cho phép … điều khiển máy này?"; SAS: so mã) rồi trả quyết định.
/// Mặc định (chưa gắn) là từ chối (fail-closed). Quá `HostAuthenticator.decisionTimeoutSeconds` coi như từ chối.
public typealias PairingDecider = @Sendable (PairingRequest) async -> PairingDecision

public enum QrClosedReason: Sendable, Equatable {
    case expired
    case paired
    case tooManyFailures
    case cancelled
}

/// Sự kiện host cho UI (cửa sổ QR, danh sách thiết bị, thông báo thu hồi).
public enum HostAuthEvent: Sendable, Equatable {
    case qrIssued(PairingURI)
    case qrClosed(QrClosedReason)
    case pairingPending(PairingRequest)
    case pairingResolved(deviceId: String, accepted: Bool)
    case sessionOpened(AuthenticatedPeer)
    case sessionClosed(deviceId: String)
    case sessionRevoked(deviceId: String)
}
