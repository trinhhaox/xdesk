import Darwin
import UIKit
import XdeskTransport

enum TailscaleState: Equatable, Sendable {
    case active
    case installedInactive
    case notInstalled

    var statusBadge: String {
        switch self {
        case .active: "Đang bật"
        case .installedInactive: "Đang tắt"
        case .notInstalled: "Chưa cài"
        }
    }

    var actionLabel: String {
        self == .notInstalled ? "Cài đặt Tailscale" : "Mở Tailscale"
    }

    var settingsSubtitle: String {
        switch self {
        case .active: "Đang bật · Sẵn sàng kết nối từ xa"
        case .installedInactive: "Đang tắt · Chạm để mở và bật"
        case .notInstalled: "Chưa cài đặt · Chạm để cài đặt"
        }
    }

    var detailDescription: String {
        switch self {
        case .active:
            "Tailscale đang bật. Bạn có thể kết nối tới máy Mac từ xa bằng IP 100.x.y.z hoặc tên MagicDNS."
        case .installedInactive:
            "Tailscale đã cài nhưng đang tắt. Bật Tailscale để kết nối máy Mac từ xa ngoài mạng Wi-Fi."
        case .notInstalled:
            "Chưa cài đặt Tailscale. Cài ứng dụng và đăng nhập cùng tài khoản với máy Mac để kết nối từ xa."
        }
    }

    var inlineHint: String {
        switch self {
        case .installedInactive:
            "Tailscale đang tắt. Bật Tailscale để kết nối qua IP 100.x.y.z hoặc *.ts.net."
        case .notInstalled:
            "Chưa cài đặt Tailscale. Cài Tailscale để kết nối từ xa qua IP 100.x.y.z."
        case .active:
            ""
        }
    }
}

/// Nhận diện địa chỉ Tailscale (`100.64.0.0/10`, `fd7a:115c:a1e0::/48`, `*.ts.net`),
/// kiểm tra trạng thái Tailscale trên iOS và mở ứng dụng / App Store khi cần.
@MainActor
enum TailscaleSupport {
    private static let appURL = URL(string: "tailscale://")!
    private static let installURL = URL(string: "https://apps.apple.com/app/tailscale/id1470499037")!

    nonisolated static func isTailscaleHost(_ raw: String) -> Bool {
        let host = extractHost(raw).lowercased()
        guard !host.isEmpty else { return false }
        if host.hasSuffix(".ts.net") { return true }
        if host.hasPrefix("fd7a:115c:a1e0:") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 4,
           let a = UInt8(parts[0]), let b = UInt8(parts[1]),
           let _ = UInt8(parts[2]), let _ = UInt8(parts[3]) {
            return InterfaceFilter.isTailscale(ipv4: [a, b, 0, 0])
        }
        return false
    }

    nonisolated private static func extractHost(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]") {
            let start = trimmed.index(after: trimmed.startIndex)
            return String(trimmed[start..<close])
        }
        let colons = trimmed.filter { $0 == ":" }.count
        if colons > 1 {
            return String(trimmed.split(separator: "%", maxSplits: 1).first ?? "")
        }
        let noPort = colons == 1 ? String(trimmed.split(separator: ":", maxSplits: 1).first ?? "") : trimmed
        return String(noPort.split(separator: "%", maxSplits: 1).first ?? "")
    }

    static func hasActiveInterface() -> Bool {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return false }
        defer { freeifaddrs(head) }
        let requiredUp = UInt32(IFF_UP)
        let excludedLoopback = UInt32(IFF_LOOPBACK)
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = entry.ifa_flags
            guard (flags & requiredUp) != 0, (flags & excludedLoopback) == 0, let sa = entry.ifa_addr else { continue }
            switch Int32(sa.pointee.sa_family) {
            case AF_INET:
                let matched = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { p in
                    withUnsafeBytes(of: p.pointee.sin_addr) { InterfaceFilter.isTailscale(ipv4: [UInt8]($0)) }
                }
                if matched { return true }
            case AF_INET6:
                let matched = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { p in
                    withUnsafeBytes(of: p.pointee.sin6_addr) { InterfaceFilter.isTailscale(ipv6: [UInt8]($0)) }
                }
                if matched { return true }
            default:
                continue
            }
        }
        return false
    }

    static func isInstalled() -> Bool {
        UIApplication.shared.canOpenURL(appURL)
    }

    static func detect() -> TailscaleState {
        if hasActiveInterface() { return .active }
        if isInstalled() { return .installedInactive }
        return .notInstalled
    }

    static func openApp() {
        UIApplication.shared.open(appURL)
    }

    static func openInstall() {
        UIApplication.shared.open(installURL)
    }

    static func openOrInstall(for state: TailscaleState) {
        if state == .notInstalled {
            openInstall()
        } else {
            openApp()
        }
    }
}
