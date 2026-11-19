import Foundation

public struct HostSnapshot: Sendable, Equatable {
    public var isSharing: Bool
    public var viewerCount: Int
    public var encryptionOn: Bool

    public init(isSharing: Bool, viewerCount: Int, encryptionOn: Bool) {
        self.isSharing = isSharing
        self.viewerCount = viewerCount
        self.encryptionOn = encryptionOn
    }
}

/// `xdesk_status`: trạng thái chỉ đọc. Màn hình agent và người giữ quyền chưa có ở phase 08a.
public struct StatusTool: ToolHandler {
    private let snapshot: @Sendable () async -> HostSnapshot

    public init(snapshot: @escaping @Sendable () async -> HostSnapshot) { self.snapshot = snapshot }

    public func call(arguments: JsonValue) async -> ToolResult {
        let host = await snapshot()
        return .ok([
            "Chia sẻ màn hình: \(host.isSharing ? "đang bật" : "đang tắt")",
            "Viewer đang xem: \(host.viewerCount)",
            "Mã hoá: \(host.encryptionOn ? "bật" : "tắt")",
            "Màn hình agent: chưa có",
            "Người giữ quyền điều khiển: không có",
        ].joined(separator: "\n"))
    }
}
