import Foundation
import os

/// Thương lượng phiên bản và quản lý phiên (Mcp-Session-Id) theo MCP revision 2025-11-25.
public enum McpProtocol {
    public static let latest = "2025-11-25"
    public static let supported = [latest, "2025-06-18"]
    public static let sessionHeader = "Mcp-Session-Id"

    /// Client xin phiên bản server hỗ trợ thì dùng đúng bản đó, nếu không trả bản mới nhất để client tự quyết định.
    public static func negotiate(_ requested: String) -> String {
        supported.contains(requested) ? requested : latest
    }

    public static func initializeResult(version: String, serverVersion: String) -> JsonValue {
        [
            "protocolVersion": .string(version),
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "xdesk", "title": "Xdesk", "version": .string(serverVersion)],
            "instructions": "Xdesk cho agent làm việc trên màn hình ảo riêng. Gọi xdesk_status để xem trạng thái; các tool điều khiển cần người dùng duyệt.",
        ]
    }
}

public final class McpSessionStore: Sendable {
    private struct State {
        var order: [String] = []
        var versions: [String: String] = [:]
    }

    private let capacity: Int
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(capacity: Int = 64) { self.capacity = capacity }

    /// Tạo phiên mới; quá `capacity` thì bỏ phiên cũ nhất để agent treo không làm đầy bộ nhớ.
    public func create(version: String) -> String {
        let id = UUID().uuidString
        state.withLock { state in
            state.order.append(id)
            state.versions[id] = version
            while state.order.count > capacity { state.versions[state.order.removeFirst()] = nil }
        }
        return id
    }

    public func contains(_ id: String) -> Bool { state.withLock { $0.versions[id] != nil } }

    public func remove(_ id: String) {
        state.withLock { state in
            state.versions[id] = nil
            state.order.removeAll { $0 == id }
        }
    }
}
