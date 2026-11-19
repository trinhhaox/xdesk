import XdeskWire

/// Cách viewer nối vào Mac này.
enum ViewerTransport: Sendable, Equatable {
    case lan, tailscale, usb

    var label: String {
        switch self {
        case .lan: "LAN"
        case .tailscale: "Tailscale"
        case .usb: "USB"
        }
    }

    var symbol: String {
        switch self {
        case .lan: "wifi"
        case .tailscale: "network"
        case .usb: "cable.connector"
        }
    }
}

/// Thông tin hiển thị của một viewer đang xem (chỉ dữ liệu, không giữ tài nguyên).
struct ViewerSessionInfo: Sendable, Equatable {
    let name: String
    let transport: ViewerTransport
    /// Ví dụ "Bản sao · Vừa thiết bị" hoặc "Mở rộng".
    let modeLabel: String

    static func make(name: String, config: DisplayConfig, isUsb: Bool, isTailscale: Bool) -> ViewerSessionInfo {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ViewerSessionInfo(
            name: trimmed.isEmpty ? "Thiết bị chưa đặt tên" : trimmed,
            transport: isUsb ? .usb : (isTailscale ? .tailscale : .lan),
            modeLabel: modeLabel(config))
    }

    static func modeLabel(_ config: DisplayConfig) -> String {
        switch config.screenMode {
        case .extend: return "Mở rộng"
        case .mirror:
            switch config.fit {
            case .native: return "Bản sao · Gốc"
            case .fitDevice: return "Bản sao · Vừa thiết bị"
            case .touch: return "Bản sao · Cảm ứng"
            }
        }
    }
}
