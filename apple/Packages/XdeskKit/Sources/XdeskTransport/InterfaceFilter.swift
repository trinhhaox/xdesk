import Foundation
import Network

/// Phân biệt kết nối đến qua Tailscale (interface `utun` mang địa chỉ CGNAT `100.64.0.0/10` hoặc ULA `fd7a:115c:a1e0::/48`).
/// Tailscale gán đúng hai dải này cho interface của nó, nên một peer có địa chỉ nguồn trong dải là kết nối đi qua tailnet.
/// Host chỉ nhận chúng khi người dùng bật "Cho phép kết nối qua Tailscale" (mặc định tắt).
public enum InterfaceFilter {
    public struct TailscaleInterface: Sendable, Equatable {
        public let name: String
        public let address: String
    }

    public static func isTailscale(ipv4 b: [UInt8]) -> Bool {
        b.count == 4 && b[0] == 100 && (64...127).contains(b[1])
    }

    public static func isTailscale(ipv6 b: [UInt8]) -> Bool {
        guard b.count == 16 else { return false }
        if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xFF && b[11] == 0xFF { return isTailscale(ipv4: Array(b[12..<16])) }
        return b[0] == 0xFD && b[1] == 0x7A && b[2] == 0x11 && b[3] == 0x5C && b[4] == 0xA1 && b[5] == 0xE0
    }

    public static func isTailscale(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let a): return isTailscale(ipv4: [UInt8](a.rawValue))
        case .ipv6(let a): return isTailscale(ipv6: [UInt8](a.rawValue))
        case .name: return false
        @unknown default: return false
        }
    }

    /// Kết nối này có được nhận không: Tailscale chỉ khi đã bật cho phép.
    public static func allows(_ endpoint: NWEndpoint, allowTailscale: Bool) -> Bool {
        allowTailscale || !isTailscale(endpoint)
    }

    /// Các interface `utun` của máy này đang mang địa chỉ Tailscale (để hiện trạng thái trong cài đặt).
    public static func tailscaleInterfaces() -> [TailscaleInterface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var found: [TailscaleInterface] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("utun"), let sa = entry.ifa_addr else { continue }
            if let text = tailscaleAddress(sa) { found.append(TailscaleInterface(name: name, address: text)) }
        }
        return found
    }

    private static func tailscaleAddress(_ sa: UnsafeMutablePointer<sockaddr>) -> String? {
        switch Int32(sa.pointee.sa_family) {
        case AF_INET:
            return sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { p -> String? in
                let bytes = withUnsafeBytes(of: p.pointee.sin_addr) { [UInt8]($0) }
                return isTailscale(ipv4: bytes) ? bytes.map(String.init).joined(separator: ".") : nil
            }
        case AF_INET6:
            return sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { p -> String? in
                let bytes = withUnsafeBytes(of: p.pointee.sin6_addr) { [UInt8]($0) }
                guard isTailscale(ipv6: bytes), let address = IPv6Address(Data(bytes)) else { return nil }
                return "\(address)"
            }
        default:
            return nil
        }
    }
}
