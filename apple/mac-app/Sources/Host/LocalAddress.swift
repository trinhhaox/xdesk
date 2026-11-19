import Darwin

/// Địa chỉ IPv4 LAN của Mac, để hiện trong menu cho người dùng nhập tay trên điện thoại.
enum LocalAddress {
    /// IPv4 đầu tiên trên giao diện đang bật (ưu tiên en0 Wi-Fi), bỏ qua loopback và link-local.
    static func primaryIPv4() -> String? {
        let found = interfaceIPv4s().filter { !isTailscale($0.ip) }
        return (found.first { $0.name == "en0" } ?? found.first)?.ip
    }

    /// IPv4 Tailscale (100.64.0.0/10, CGNAT) của Mac nếu đang bật Tailscale; dùng cho mã QR khi cho phép kết nối qua Tailscale.
    static func tailscaleIPv4() -> String? {
        interfaceIPv4s().first { isTailscale($0.ip) }?.ip
    }

    static func isTailscale(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        return parts.count == 4 && parts[0] == 100 && (64...127).contains(parts[1])
    }

    static func interfaceIPv4s() -> [(name: String, ip: String)] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var found: [(name: String, ip: String)] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = entry.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  (ifa.ifa_flags & UInt32(IFF_UP)) != 0, (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if ip.hasPrefix("169.254.") { continue }
            found.append((String(cString: ifa.ifa_name), ip))
        }
        return found
    }
}
