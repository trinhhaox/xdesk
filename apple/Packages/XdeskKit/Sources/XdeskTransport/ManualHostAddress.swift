import Foundation

/// Địa chỉ host nhập tay: IPv4 (vd. Tailscale `100.101.102.103`) hoặc tên miền/MagicDNS (`mac.tail1234.ts.net`), tuỳ chọn `:cổng`.
public struct ManualHostAddress: Sendable, Equatable {
    public static let defaultPort: UInt16 = 47800

    public let host: String
    public let port: UInt16

    /// Dạng chuẩn `host:port` (host viết thường), dùng làm khoá lưu.
    public var normalized: String { "\(host):\(port)" }

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        let port: UInt16
        if parts.count == 2 {
            guard let value = UInt16(parts[1]), value > 0 else { return nil }
            port = value
        } else {
            port = Self.defaultPort
        }
        let host = String(parts[0])
        // Chỉ gồm số và dấu chấm thì phải là IPv4 đủ 4 phần (tránh "100.1.2" bị coi là tên máy).
        let looksNumeric = host.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2E }
        guard looksNumeric ? Self.isValidIPv4(host) : Self.isValidHostName(host) else { return nil }
        self.host = host
        self.port = port
    }

    private static func isValidIPv4(_ text: String) -> Bool {
        let octets = text.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.allSatisfy { !$0.isEmpty && $0.count <= 3 && UInt8($0) != nil }
    }

    private static func isValidHostName(_ text: String) -> Bool {
        guard !text.isEmpty, text.utf8.count <= 253 else { return false }
        return text.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            !label.isEmpty && label.utf8.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.utf8.allSatisfy { ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D }
        }
    }
}
