import XdeskCrypto
import XdeskTransport

/// Một máy Mac đã ghép trên màn hình chính: gộp host đã ghép + Bonjour + máy nhập tay theo fingerprint.
public struct PairedHostRow: Equatable, Sendable, Identifiable {
    public enum Status: Equatable, Sendable {
        /// Đang thấy trên LAN (Bonjour).
        case ready
        /// Không thấy trên LAN nhưng còn địa chỉ `host:port` đã dùng lần trước.
        case viaAddress(String)
        case offline

        public var text: String {
            switch self {
            case .ready: "Sẵn sàng"
            case .viaAddress(let address): "Qua địa chỉ \(address)"
            case .offline: "Không thấy trên mạng"
            }
        }

        fileprivate var rank: Int {
            switch self {
            case .ready: 0
            case .viaAddress: 1
            case .offline: 2
            }
        }
    }

    public let device: PairedDevice
    public let status: Status
    /// Địa chỉ nhập tay đã lưu thuộc về máy này (xoá cùng lúc khi quên máy).
    public let savedAddresses: [String]

    public var id: String { device.id }
}

public enum PairedHostListing {
    /// Mọi host (role host) đã ghép, kể cả khi không thấy trên mạng. Thứ tự: Sẵn sàng, Qua địa chỉ, Không thấy; trong nhóm theo
    /// lần dùng gần nhất rồi tên.
    public static func rows(paired: [PairedDevice], discoveredIds: Set<String>, manual: [ManualHost]) -> [PairedHostRow] {
        paired.filter { $0.role == .host }.map { device in
            let saved = savedHosts(for: device, in: manual).map(\.address)
            let status: PairedHostRow.Status
            if discoveredIds.contains(device.id) {
                status = .ready
            } else if let address = device.lastAddress {
                status = .viaAddress(address)
            } else {
                status = .offline
            }
            return PairedHostRow(device: device, status: status, savedAddresses: saved)
        }
        .sorted {
            ($0.status.rank, $1.device.lastSeen ?? .distantPast, $0.device.name)
                < ($1.status.rank, $0.device.lastSeen ?? .distantPast, $1.device.name)
        }
    }

    /// Máy nhập tay chưa thuộc máy đã ghép nào (vẫn hiện ở mục "Máy đã lưu").
    public static func unmergedManual(_ manual: [ManualHost], rows: [PairedHostRow]) -> [ManualHost] {
        let merged = Set(rows.flatMap(\.savedAddresses))
        return manual.filter { !merged.contains($0.address) }
    }

    /// Host Bonjour chưa ghép (kể cả đổi khoá) → mục "Máy Mac khác trên mạng".
    public static func unpairedIds(discoveredIds: [String], rows: [PairedHostRow]) -> [String] {
        let paired = Set(rows.map(\.id))
        return discoveredIds.filter { !paired.contains($0) }
    }

    private static func savedHosts(for device: PairedDevice, in manual: [ManualHost]) -> [ManualHost] {
        guard let address = device.lastAddress else { return [] }
        return manual.filter { $0.address == address || $0.lastAddress == address }
    }
}
