import XdeskTransport

/// Lỗi kết nối dạng người đọc được: câu mô tả, gợi ý khắc phục và thông báo kỹ thuật gốc ("Chi tiết").
/// `ViewerSession.State.failed` chỉ mang chuỗi `localizedDescription` của `TransportError`, nên phân loại bằng cách so với chính
/// `errorDescription` của từng case (không lặp lại câu chữ của gói XdeskKit).
struct ConnectionFailure: Equatable {
    enum Action { case retry, pairAgain }

    let title: String
    let hint: String?
    let detail: String?
    let symbol: String
    let action: Action

    private static let unreachableHint = "Kiểm tra Mac đã bật chia sẻ và cùng mạng, hoặc dùng Tailscale."

    static func make(message: String, hostName: String?) -> ConnectionFailure {
        let name = hostName.map { "\"\($0)\"" } ?? "máy Mac"
        func match(_ error: TransportError) -> Bool { message == error.errorDescription }

        if match(.timedOut) {
            return .init(title: "\(name) không phản hồi.", hint: unreachableHint, detail: message, symbol: "wifi.exclamationmark", action: .retry)
        }
        if message.hasPrefix(TransportError.connectionFailed("").errorDescription ?? "\u{0}") {
            return .init(title: "Không kết nối được tới \(name).", hint: unreachableHint, detail: message, symbol: "wifi.exclamationmark", action: .retry)
        }
        if match(.connectionClosed) {
            return .init(title: "Kết nối tới \(name) đã bị ngắt.", hint: "Thử kết nối lại. Nếu vẫn lỗi, kiểm tra Mac chưa ngủ hay tắt chia sẻ.", detail: message, symbol: "bolt.horizontal.circle", action: .retry)
        }
        if match(.pairingRequired) || match(.unknownDevice) {
            return .init(title: "Chưa ghép đôi với \(name).", hint: "Ghép đôi một lần bằng mã QR hoặc mã 6 số, những lần sau tự kết nối.", detail: message, symbol: "link.badge.plus", action: .pairAgain)
        }
        if match(.reconnectRefused) || match(.revokedByHost) {
            return .init(title: "\(name) không còn nhận thiết bị này.", hint: "Có thể đã bấm \"Thu hồi\" trên Mac. Ghép đôi lại để dùng tiếp.", detail: message, symbol: "lock.slash", action: .pairAgain)
        }
        if match(.hostKeyMismatch) {
            return .init(title: "Khoá bảo mật của \(name) đã đổi.", hint: "Xdesk không kết nối để tránh bị mạo danh. Chỉ quên khoá cũ nếu Mac vừa được cài lại.", detail: message, symbol: "exclamationmark.shield", action: .retry)
        }
        return .init(title: message, hint: nil, detail: nil, symbol: "exclamationmark.triangle", action: .retry)
    }
}
