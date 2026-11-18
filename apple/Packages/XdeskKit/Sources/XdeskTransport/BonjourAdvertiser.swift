import Network

/// Mô tả dịch vụ Bonjour `_xdesk._tcp` của host. TXT: `v` (phiên bản wire), `id` (fingerprint ngắn), `n` (tên Mac).
public struct BonjourAdvertiser: Sendable, Equatable {
    public static let serviceType = "_xdesk._tcp"
    public static let txtVersionKey = "v"
    public static let txtIdKey = "id"
    public static let txtNameKey = "n"

    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public var txtEntries: [String: String] {
        [Self.txtVersionKey: "1", Self.txtIdKey: id, Self.txtNameKey: name]
    }

    /// Gán vào `NWListener.service` để listener tự quảng bá.
    var service: NWListener.Service {
        NWListener.Service(
            name: name, type: Self.serviceType,
            txtRecord: NWTXTRecord(txtEntries)
        )
    }
}
