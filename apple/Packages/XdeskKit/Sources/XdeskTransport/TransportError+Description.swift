import Foundation

/// Thông báo tiếng Việt cho UI (`error.localizedDescription`). Không chứa khoá/token.
extension TransportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let detail): "Không kết nối được: \(detail)"
        case .connectionClosed: "Kết nối đã đóng"
        case .timedOut: "Hết thời gian chờ"
        case .protocolViolation(let detail): "Đối tác vi phạm giao thức: \(detail)"
        case .rejected(let reason, let detail): "Host từ chối (\(reason))" + (detail.map { ": \($0)" } ?? "")
        case .encryptionUnavailable: "Kênh mã hoá chưa sẵn sàng"
        case .listenerFailed(let detail): "Không mở được cổng nghe: \(detail)"
        case .noPeer: "Chưa có thiết bị đối tác"
        case .unknownDevice: "Thiết bị chưa được ghép đôi với máy này"
        case .pairingClosed: "Máy host không mở ghép đôi (mã QR đã dùng hoặc hết hạn)"
        case .pairingLimited: "Ghép đôi bằng mã bị khoá tạm thời do thử sai quá nhiều lần"
        case .commitmentMismatch: "Mã so khớp không hợp lệ"
        case .pairingDenied: "Máy host đã từ chối ghép đôi"
        case .pairingRequired: "Chưa ghép đôi với máy này: quét mã QR hoặc so mã 6 số"
        case .hostKeyMismatch: "Khoá của máy host không khớp (host cài lại hoặc thiết bị mạo danh): không kết nối"
        case .revokedByHost: "Máy Mac đã thu hồi quyền của thiết bị này. Ghép đôi lại để dùng tiếp."
        case .reconnectRefused: "Máy Mac từ chối kết nối, có thể đã thu hồi thiết bị này. Ghép đôi lại để dùng tiếp."
        }
    }
}
