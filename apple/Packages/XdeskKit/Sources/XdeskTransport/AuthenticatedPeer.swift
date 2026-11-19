import XdeskCrypto

/// Đối tác đã xác thực bằng Noise: danh tính, quyền áp dụng và cách xác thực.
public struct AuthenticatedPeer: Sendable, Equatable {
    public enum Method: Sendable, Equatable {
        /// IK với khoá đã ghép từ trước.
        case reconnect
        /// Vừa ghép đôi bằng QR (XXpsk3), host đã duyệt.
        case qrPaired
        /// Vừa ghép đôi bằng mã 6 số (XX), host đã bấm "Khớp".
        case sasPaired
    }

    public let publicKey: [UInt8]
    public let deviceId: String
    public let name: String
    public let role: DeviceRole
    public let permissions: DevicePermissions
    public let method: Method

    public init(publicKey: [UInt8], name: String, role: DeviceRole, permissions: DevicePermissions, method: Method) {
        self.publicKey = publicKey
        self.deviceId = DeviceFingerprint.make(publicKey: publicKey)
        self.name = name
        self.role = role
        self.permissions = permissions
        self.method = method
    }
}
