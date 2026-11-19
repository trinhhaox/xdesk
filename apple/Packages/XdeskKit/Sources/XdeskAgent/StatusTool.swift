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

/// Màn hình agent (nil = chưa tạo) và người giữ quyền điều khiển.
public struct AgentStatus: Sendable, Equatable {
    public var display: AgentDisplayGeometry?
    public var control: ControlSnapshot

    public init(display: AgentDisplayGeometry? = nil, control: ControlSnapshot = ControlSnapshot()) {
        self.display = display; self.control = control
    }
}

/// `xdesk_status`: trạng thái chỉ đọc, không cần quyền điều khiển.
public struct StatusTool: ToolHandler {
    private let snapshot: @Sendable () async -> HostSnapshot
    private let agent: @Sendable () async -> AgentStatus

    public init(snapshot: @escaping @Sendable () async -> HostSnapshot, agent: @escaping @Sendable () async -> AgentStatus = { AgentStatus() }) {
        self.snapshot = snapshot
        self.agent = agent
    }

    public func call(arguments: JsonValue) async -> ToolResult {
        let host = await snapshot()
        let agent = await agent()
        return .ok([
            "Chia sẻ màn hình: \(host.isSharing ? "đang bật" : "đang tắt")",
            "Viewer đang xem: \(host.viewerCount)",
            "Mã hoá: \(host.encryptionOn ? "bật" : "tắt")",
            "Màn hình agent: \(agent.display.map { "\($0.width)x\($0.height) px" } ?? "chưa có")",
            "Người giữ quyền điều khiển: \(agent.control.summary)",
        ].joined(separator: "\n"))
    }
}
