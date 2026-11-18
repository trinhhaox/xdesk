import Foundation
import XdeskTransport

/// Đích kết nối của viewer: host tìm thấy qua Bonjour hoặc nhập tay `host:port`.
public enum ViewerTarget: Sendable, Equatable {
    case discovered(DiscoveredHost)
    case manual(host: String, port: UInt16)

    /// `host:port` (IPv4/tên miền). Trả `nil` nếu sai định dạng.
    public static func parse(manual text: String) -> ViewerTarget? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, let port = UInt16(parts[1]), port > 0 else { return nil }
        return .manual(host: String(parts[0]), port: port)
    }
}
