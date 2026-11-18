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
    public enum Update: Sendable, Equatable {
        case hosts([DiscoveredHost])
        /// iOS: người dùng từ chối quyền Mạng nội bộ → browse không bao giờ có kết quả.
        case localNetworkDenied
    }

    /// `kDNSServiceErr_PolicyDenied`: NWBrowser báo mã này (qua `.waiting`) khi thiếu quyền Local Network.
    static let policyDeniedCode: Int32 = -65570

    public init() {}

    /// Kết thúc stream (hoặc huỷ task đọc) sẽ dừng browser.
    public func hosts() -> AsyncStream<[DiscoveredHost]> {
        let updates = updates()
        return AsyncStream { continuation in
            let task = Task {
                for await update in updates {
                    if case .hosts(let list) = update { continuation.yield(list) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func updates() -> AsyncStream<Update> {
        AsyncStream { continuation in
            let browser = NWBrowser(
                for: .bonjourWithTXTRecord(type: BonjourAdvertiser.serviceType, domain: nil), using: .tcp
            )
            browser.browseResultsChangedHandler = { results, _ in
                continuation.yield(.hosts(results.compactMap(Self.host(from:)).sorted { $0.name < $1.name }))
            }
            browser.stateUpdateHandler = { state in
                switch state {
                case .failed: continuation.finish()
                case .waiting(let error) where Self.isPolicyDenied(error): continuation.yield(.localNetworkDenied)
                default: break
                }
            }
            continuation.onTermination = { _ in browser.cancel() }
            browser.start(queue: DispatchQueue(label: "xdesk.bonjour.browser"))
        }
    }

    static func isPolicyDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == policyDeniedCode }
        return false
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
