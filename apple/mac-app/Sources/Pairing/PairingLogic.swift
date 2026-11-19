import Foundation
import XdeskCrypto
import XdeskTransport

/// Mac có được hiện mã QR lúc này không. QR chứa token ghép đôi nên chỉ hiện khi không ai đang xem màn hình này
/// (viewer đang stream có thể nhìn thấy mã) và khi host đang chạy ở chế độ mã hoá.
enum PairingAvailability: Equatable {
    case ready(port: UInt16)
    case hostStopped
    case plaintextMode
    case sessionActive(viewers: Int)

    static func evaluate(encrypted: Bool, port: UInt16?, activeViewers: Int) -> PairingAvailability {
        guard encrypted else { return .plaintextMode }
        guard let port else { return .hostStopped }
        return activeViewers > 0 ? .sessionActive(viewers: activeViewers) : .ready(port: port)
    }

    /// Lý do (một câu, kèm cách khắc phục) khi chưa hiện được QR; nil khi sẵn sàng.
    var blockedMessage: String? {
        switch self {
        case .ready: nil
        case .hostStopped: "Chưa bật chia sẻ màn hình. Hãy chọn \"Bắt đầu chia sẻ màn hình\" trong menu rồi mở lại cửa sổ này."
        case .plaintextMode: "Bản thử nghiệm đang chạy không mã hoá nên không có ghép đôi. Hãy chạy lại không kèm --plaintext."
        case .sessionActive: "Đang có thiết bị xem màn hình này. Để người đó không nhìn thấy mã, Xdesk chỉ hiện mã khi không ai đang xem. Hãy ngắt kết nối rồi thử lại."
        }
    }
}

/// Lựa chọn quyền ở hộp thoại cho phép ghép đôi. "Xem màn hình" luôn bật; mặc định xem + điều khiển, QR hay mã 6 số đều phải bấm xác nhận.
struct ApprovalDraft: Equatable {
    var input = DevicePermissions.default.input
    var clipboard = DevicePermissions.default.clipboard
    var audio = DevicePermissions.default.audio

    var permissions: DevicePermissions {
        DevicePermissions(view: true, input: input, clipboard: clipboard, audio: audio)
    }
}

enum PairingCountdown {
    /// Số giây còn lại của mã QR (không âm). Token sống `PairingToken.lifetime` giây từ lúc phát hành.
    static func remaining(issuedAt: Date, now: Date, lifetime: TimeInterval = PairingToken.lifetime) -> Int {
        max(0, Int((lifetime - now.timeIntervalSince(issuedAt)).rounded(.up)))
    }

    static func label(seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

extension PairingRequest.Method {
    var title: String {
        switch self {
        case .qr: "Quét mã QR"
        case .sas: "So mã 6 số"
        }
    }
}
