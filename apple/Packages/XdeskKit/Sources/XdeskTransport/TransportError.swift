/// Lỗi tầng transport (lỗi giải mã wire được ném nguyên dạng `WireError`).
public enum TransportError: Error, Sendable, Equatable {
    case connectionFailed(String)
    case connectionClosed
    case timedOut
    case protocolViolation(String)
    case rejected(reason: String, detail: String?)
    /// Chưa có khoá phiên (kết nối mã hoá chưa bắt tay xong).
    case encryptionUnavailable
    case listenerFailed(String)
    case noPeer
    /// IK: khoá viewer không có trong danh sách đã ghép (host không trả lời gì).
    case unknownDevice
    /// Host không mở ghép đôi (không có token QR hiệu lực) hoặc token đã dùng/hết hạn.
    case pairingClosed
    /// SAS: quá 3 lần hỏng trong 10 phút.
    case pairingLimited
    /// SAS: cam kết của viewer không khớp khoá/nonce nhận được.
    case commitmentMismatch
    /// Người dùng ở host từ chối (hoặc hết thời gian chờ).
    case pairingDenied
    /// Viewer: chưa ghép đôi với host này (không có khoá để IK).
    case pairingRequired
    /// Viewer: khoá tĩnh host khác `h` trong QR / khác khoá đã lưu (nghi MITM hoặc host cài lại).
    case hostKeyMismatch
    /// Viewer: host báo (qua kênh đã mã hoá) đã thu hồi thiết bị này; host đã bị xoá khỏi danh sách đã biết.
    case revokedByHost
    /// Viewer: host đã ghép đóng kết nối ngay trong bắt tay IK (thường do đã thu hồi lúc viewer không kết nối).
    /// Tín hiệu chưa xác thực nên không tự xoá host; UI đề nghị người dùng ghép đôi lại.
    case reconnectRefused
}
