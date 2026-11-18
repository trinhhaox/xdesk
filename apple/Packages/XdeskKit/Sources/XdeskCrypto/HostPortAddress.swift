import Foundation

/// Địa chỉ ứng viên trong QR: `ipv4:port`, `[ipv6]:port` hoặc `hostname:port`, port 1…65535 (chỉ chữ số).
/// Từ chối mọi thứ khác (đường dẫn, `user@`, scheme, khoảng trắng, IPv6 không ngoặc, zone `%`), để QR lạ không điều khiển viewer
/// kết nối tới endpoint tuỳ ý theo cú pháp bất ngờ.
enum HostPortAddress {
    static func isValid(_ text: String) -> Bool {
        guard text.utf8.count <= PairingURI.maxAddressLength, let split = splitHostAndPort(text) else { return false }
        guard let port = Int(split.port), split.port.utf8.allSatisfy({ (48...57).contains($0) }), split.port.utf8.count <= 5,
              (1...65535).contains(port) else { return false }
        return split.isIPv6 ? isIPv6(split.host) : (isIPv4(split.host) || isHostname(split.host))
    }

    private static func splitHostAndPort(_ text: String) -> (host: String, port: String, isIPv6: Bool)? {
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]") else { return nil }
            let rest = text[text.index(after: close)...]
            guard rest.hasPrefix(":") else { return nil }
            return (String(text[text.index(after: text.startIndex)..<close]), String(rest.dropFirst()), true)
        }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]), false)
    }

    private static func isIPv4(_ host: String) -> Bool {
        var address = in_addr()
        return host.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || $0 == 46 } && inet_pton(AF_INET, host, &address) == 1
    }

    private static func isIPv6(_ host: String) -> Bool {
        var address = in6_addr()
        return host.contains(":") && !host.contains("%") && inet_pton(AF_INET6, host, &address) == 1
    }

    /// RFC 1123: nhãn 1…63 ký tự `[A-Za-z0-9-]`, không bắt đầu/kết thúc bằng `-`, tổng ≤ 253; nhãn cuối không thuần số (tránh IPv4 hỏng lọt qua).
    private static func isHostname(_ host: String) -> Bool {
        guard !host.isEmpty, host.utf8.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let validLabels = labels.allSatisfy { label in
            (1...63).contains(label.utf8.count) && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45 }
        }
        return validLabels && !(labels.last?.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } ?? true)
    }
}
