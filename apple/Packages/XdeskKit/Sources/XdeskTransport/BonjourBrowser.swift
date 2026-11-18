import Network

/// Một host tìm thấy qua Bonjour.
public struct DiscoveredHost: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let wireVersion: String
    public let endpoint: NWEndpoint
}

/// Liệt kê host `_xdesk._tcp` trên LAN. Mỗi lần danh sách đổi, stream phát lại toàn bộ danh sách.
public struct BonjourBrowser: Sendable {
    public init() {}

    /// Kết thúc stream (hoặc huỷ task đọc) sẽ dừng browser.
    public func hosts() -> AsyncStream<[DiscoveredHost]> {
        AsyncStream { continuation in
            let browser = NWBrowser(
                for: .bonjourWithTXTRecord(type: BonjourAdvertiser.serviceType, domain: nil), using: .tcp
            )
            browser.browseResultsChangedHandler = { results, _ in
                continuation.yield(results.compactMap(Self.host(from:)).sorted { $0.name < $1.name })
            }
            browser.stateUpdateHandler = { state in
                if case .failed = state { continuation.finish() }
            }
            continuation.onTermination = { _ in browser.cancel() }
            browser.start(queue: DispatchQueue(label: "xdesk.bonjour.browser"))
        }
    }

    /// Bỏ qua mục thiếu TXT `id` (không phải Xdesk hợp lệ).
    static func host(from result: NWBrowser.Result) -> DiscoveredHost? {
        guard case .bonjour(let txt) = result.metadata, let id = txt[BonjourAdvertiser.txtIdKey], !id.isEmpty else { return nil }
        return DiscoveredHost(
            id: id, name: txt[BonjourAdvertiser.txtNameKey] ?? id,
            wireVersion: txt[BonjourAdvertiser.txtVersionKey] ?? "1", endpoint: result.endpoint
        )
    }
}
