import Foundation
import Network

extension ControlListener {
    /// Đường hầm USB: Mac là TCP-client nhưng vẫn là responder của Noise. Gửi `usbHello` rồi chạy đúng bắt tay như kết nối Wi-Fi
    /// (IK/ghép đôi, giới hạn chưa xác thực, quyền theo thiết bị). Chỉ ở chế độ mã hoá.
    public func adoptUsbTunnel(_ nwConnection: NWConnection, hostPublicKey: [UInt8]) async throws {
        guard security == .encrypted, let authenticator else {
            nwConnection.cancel()
            throw TransportError.encryptionUnavailable
        }
        guard listener != nil else {
            nwConnection.cancel()
            throw TransportError.listenerFailed("host chưa chạy")
        }
        // Bắt tay chạy nền (viewer là bên mở đầu Noise): hàm này trả về ngay, người gọi không bị giữ tới khi bắt tay xong.
        Task { await self.admitSecure(nwConnection, authenticator, usbHello: hostPublicKey) }
    }
}
