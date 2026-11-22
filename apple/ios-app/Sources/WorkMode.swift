import XdeskWire

/// Chế độ làm việc thống nhất (2 chế độ xem màn hình + 3 chế độ điều khiển từ xa),
/// cài mặc định trong Cài đặt và chuyển đổi trực tiếp ngay khi đang kết nối Mac.
enum WorkMode: String, CaseIterable, Identifiable, Sendable {
    case mirror
    case extend
    case trackpad
    case keyboard
    case numpadMedia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mirror: "Chiếu màn hình Mac"
        case .extend: "Màn hình phụ"
        case .trackpad: "Chuột cảm ứng"
        case .keyboard: "Bàn phím ảo"
        case .numpadMedia: "Trình chiếu & Phím số"
        }
    }

    var shortTitle: String {
        switch self {
        case .mirror: "Chiếu Mac"
        case .extend: "Màn phụ"
        case .trackpad: "Chuột"
        case .keyboard: "Bàn phím"
        case .numpadMedia: "Slide & Số"
        }
    }

    var summary: String {
        switch self {
        case .mirror: "Hiện đúng màn hình Mac để xem và chạm trực tiếp."
        case .extend: "Biến điện thoại thành màn hình thứ hai bên cạnh Mac."
        case .trackpad: "Biến màn hình điện thoại thành bàn di chuột không dây cho Mac."
        case .keyboard: "Gõ tiếng Việt, dùng phím tắt Mac (⌘ ⌥ ⌃ ⇧) và cụm mũi tên."
        case .numpadMedia: "Điều khiển thuyết trình slide (F5, lùi/tiến) và bàn phím số."
        }
    }

    var symbol: String {
        switch self {
        case .mirror: "macbook"
        case .extend: "rectangle.on.rectangle"
        case .trackpad: "computermouse.fill"
        case .keyboard: "keyboard.fill"
        case .numpadMedia: "play.rectangle.fill"
        }
    }

    var screenMode: ScreenMode? {
        switch self {
        case .mirror: .mirror
        case .extend: .extend
        case .trackpad, .keyboard, .numpadMedia: nil
        }
    }

    var isVideoMode: Bool { screenMode != nil }
    var isControlMode: Bool { screenMode == nil }

    static func fromStorage(_ raw: String?, fallback: ScreenMode) -> WorkMode {
        if let raw, let parsed = WorkMode(rawValue: raw) { return parsed }
        return fallback == .extend ? .extend : .mirror
    }
}
