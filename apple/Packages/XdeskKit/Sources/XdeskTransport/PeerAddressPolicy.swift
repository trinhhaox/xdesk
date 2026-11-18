import Foundation
import Network

/// Chỉ chấp nhận peer từ loopback / LAN riêng / link-local / Tailscale (CGNAT 100.64/10, ULA fc00::/7).
public enum PeerAddressPolicy {
    public static func isAllowed(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let a): return isLocal(ipv4: [UInt8](a.rawValue))
        case .ipv6(let a): return isLocal(ipv6: [UInt8](a.rawValue))
        case .name: return false
        @unknown default: return false
        }
    }

    public static func isLocal(ipv4 b: [UInt8]) -> Bool {
        guard b.count == 4 else { return false }
        switch (b[0], b[1]) {
        case (127, _), (10, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        case (100, 64...127): return true
        default: return false
        }
    }

    public static func isLocal(ipv6 b: [UInt8]) -> Bool {
        guard b.count == 16 else { return false }
        if b[0..<15].allSatisfy({ $0 == 0 }) && b[15] == 1 { return true }
        if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xFF && b[11] == 0xFF { return isLocal(ipv4: Array(b[12..<16])) }
        return b[0] & 0xFE == 0xFC || (b[0] == 0xFE && b[1] & 0xC0 == 0x80)
    }

    /// Dạng chuẩn để so sánh host: bỏ `%scope` và tiền tố `::ffff:` của IPv4-mapped.
    public static func normalized(_ host: NWEndpoint.Host) -> String {
        var text = "\(host)"
        if let pct = text.firstIndex(of: "%") { text = String(text[..<pct]) }
        if text.lowercased().hasPrefix("::ffff:") { text = String(text.dropFirst(7)) }
        return text
    }
}
