import Foundation

/// Quyền hệ thống Xdesk cần; mỗi quyền có câu giải thích ngắn và đường dẫn thẳng tới trang Quyền riêng tư tương ứng.
enum PermissionKind: String, CaseIterable, Sendable, Identifiable {
    case screenRecording, accessibility, inputMonitoring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenRecording: "Ghi màn hình"
        case .accessibility: "Trợ năng"
        case .inputMonitoring: "Giám sát đầu vào"
        }
    }

    var reason: String {
        switch self {
        case .screenRecording: "Để chia sẻ màn hình tới thiết bị khác."
        case .accessibility: "Để điều khiển Mac từ thiết bị khác."
        case .inputMonitoring: "Để agent AI tự dừng khi bạn chạm vào màn hình của nó."
        }
    }

    var symbol: String {
        switch self {
        case .screenRecording: "record.circle"
        case .accessibility: "accessibility"
        case .inputMonitoring: "keyboard"
        }
    }

    var settingsURL: URL? {
        let pane = switch self {
        case .screenRecording: "Privacy_ScreenCapture"
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
    }

    /// Các quyền còn thiếu theo thứ tự cố định; Giám sát đầu vào chỉ tính khi agent AI cần tới nó.
    static func missing(screenRecording: Bool, accessibility: Bool, inputMonitoringNeeded: Bool) -> [PermissionKind] {
        var result: [PermissionKind] = []
        if !screenRecording { result.append(.screenRecording) }
        if !accessibility { result.append(.accessibility) }
        if inputMonitoringNeeded { result.append(.inputMonitoring) }
        return result
    }
}

/// Trạng thái viên thuốc ở đầu popover.
enum StatusPill: Equatable, Sendable {
    case sharing, stopped, needsPermission, failed

    var title: String {
        switch self {
        case .sharing: "Đang chia sẻ"
        case .stopped: "Đã dừng"
        case .needsPermission: "Cần cấp quyền"
        case .failed: "Gặp lỗi"
        }
    }

    /// Thiếu quyền Ghi màn hình là chặn hẳn việc chia sẻ nên ưu tiên cao nhất; thiếu quyền khác chỉ hiện ở thẻ quyền.
    static func evaluate(isHosting: Bool, failed: Bool, missing: [PermissionKind]) -> StatusPill {
        if missing.contains(.screenRecording) { return .needsPermission }
        if failed { return .failed }
        return isHosting ? .sharing : .stopped
    }
}

/// Định dạng địa chỉ: cổng luôn là số trần ("47810"), không có dấu phân cách hàng nghìn của ngôn ngữ.
enum EndpointFormat {
    static func hostPort(_ host: String, _ port: UInt16) -> String { "\(host):\(String(port))" }
}

/// Phát hiện Tailscale: interface bất kỳ mang địa chỉ CGNAT 100.64.0.0/10 (không phụ thuộc tên `utunN`).
enum TailscaleDetector {
    static func firstAddress(in interfaces: [(name: String, ip: String)]) -> String? {
        interfaces.first { LocalAddress.isTailscale($0.ip) }?.ip
    }

    static func current() -> String? { firstAddress(in: LocalAddress.interfaceIPv4s()) }
}

/// Một dòng kênh kết nối trong popover/cài đặt.
enum TailscaleLine {
    static func text(allowed: Bool, address: String?, port: UInt16?) -> String {
        guard let address else { return allowed ? "Tailscale: chưa bật trên máy này" : "Tailscale: tắt" }
        let endpoint = port.map { EndpointFormat.hostPort(address, $0) } ?? address
        return allowed ? "Tailscale \(endpoint)" : "Tailscale \(address) · đang tắt trong Cài đặt"
    }
}
