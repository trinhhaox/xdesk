import Darwin

/// Địa chỉ IPv4 LAN của Mac, để hiện trong menu cho người dùng nhập tay trên điện thoại.
enum LocalAddress {
    /// IPv4 đầu tiên trên giao diện đang bật (ưu tiên en0 Wi-Fi), bỏ qua loopback và link-local.
    static func primaryIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
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
        return (found.first { $0.name == "en0" } ?? found.first)?.ip
    }
}
