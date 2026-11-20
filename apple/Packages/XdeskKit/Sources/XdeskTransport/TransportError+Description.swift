import Foundation

/// Thông báo cho UI (`error.localizedDescription`); nguồn tiếng Việt, bản dịch en trong Localizable.xcstrings. Không chứa khoá/token.
extension TransportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let detail): String(localized: "Không kết nối được: \(detail)", bundle: .module)
        case .connectionClosed: String(localized: "Kết nối đã đóng", bundle: .module)
        case .timedOut: String(localized: "Hết thời gian chờ", bundle: .module)
        case .protocolViolation(let detail): String(localized: "Đối tác vi phạm giao thức: \(detail)", bundle: .module)
        case .rejected(let reason, let detail):
            if let detail { String(localized: "Host từ chối (\(reason)): \(detail)", bundle: .module) }
            else { String(localized: "Host từ chối (\(reason))", bundle: .module) }
        case .encryptionUnavailable: String(localized: "Kênh mã hoá chưa sẵn sàng", bundle: .module)
        case .listenerFailed(let detail): String(localized: "Không mở được cổng nghe: \(detail)", bundle: .module)
        case .noPeer: String(localized: "Chưa có thiết bị đối tác", bundle: .module)
        case .unknownDevice: String(localized: "Thiết bị chưa được ghép đôi với máy này", bundle: .module)
        case .pairingClosed: String(localized: "Máy host không mở ghép đôi (mã QR đã dùng hoặc hết hạn)", bundle: .module)
        case .pairingLimited: String(localized: "Ghép đôi bằng mã bị khoá tạm thời do thử sai quá nhiều lần", bundle: .module)
        case .commitmentMismatch: String(localized: "Mã so khớp không hợp lệ", bundle: .module)
        case .pairingDenied: String(localized: "Máy host đã từ chối ghép đôi", bundle: .module)
        case .pairingRequired: String(localized: "Chưa ghép đôi với máy này: quét mã QR hoặc so mã 6 số", bundle: .module)
        case .hostKeyMismatch: String(localized: "Khoá của máy host không khớp (host cài lại hoặc thiết bị mạo danh): không kết nối", bundle: .module)
        case .revokedByHost: String(localized: "Máy Mac đã thu hồi quyền của thiết bị này. Ghép đôi lại để dùng tiếp.", bundle: .module)
        case .reconnectRefused: String(localized: "Máy Mac từ chối kết nối, có thể đã thu hồi thiết bị này. Ghép đôi lại để dùng tiếp.", bundle: .module)
        }
    }
}
