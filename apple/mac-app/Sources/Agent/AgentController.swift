import AppKit
import Foundation
import Observation
import os
import XdeskAgent

/// Bật/tắt máy chủ MCP cho agent AI (mặc định TẮT), giữ token và sao chép lệnh cấu hình.
@MainActor
@Observable
final class AgentController {
    static let defaultPort: UInt16 = 47810
    private static let enabledKey = "mcp.enabled"
    private static let portKey = "mcp.port"

    enum Status: Equatable {
        case stopped
        case running(port: UInt16)
        case failed(String)
    }

    private(set) var status: Status = .stopped
    private(set) var isEnabled: Bool
    /// Thông báo ngắn sau khi chép/đổi token (không chứa token).
    private(set) var notice: String?

    private let log = Logger(subsystem: "vn.xox.xdesk", category: "mcp")
    private let host: HostController
    private let defaults: UserDefaults
    private let tokenStore = McpTokenStore()
    private let listener = McpHttpListener()

    init(host: HostController, defaults: UserDefaults = .standard) {
        self.host = host
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    var port: UInt16 {
        let stored = defaults.integer(forKey: Self.portKey)
        return (1024...65535).contains(stored) ? UInt16(stored) : Self.defaultPort
    }

    func restoreIfEnabled() async { if isEnabled { await start() } }

    /// `persist: false` cho cờ tự động hoá Debug để không đổi cài đặt người dùng.
    func setEnabled(_ enabled: Bool, persist: Bool = true) async {
        if persist { defaults.set(enabled, forKey: Self.enabledKey) }
        isEnabled = enabled
        if enabled { await start() } else { stop() }
    }

    func copySetupCommand() {
        guard case .running(let port) = status, let token = tokenStore.cachedToken else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(McpToken.claudeCodeCommand(port: port, token: token), forType: .string)
        // Quy ước nspasteboard.org: trình quản lý clipboard bỏ qua mục này, token không nằm lại trong lịch sử.
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        notice = "Đã sao chép lệnh cấu hình"
    }

    func rotateToken() {
        do {
            _ = try tokenStore.rotate()
            notice = "Đã đổi token, hãy sao chép lệnh cấu hình mới"
        } catch {
            log.error("Đổi token MCP lỗi: \(String(describing: error), privacy: .public)")
            notice = "Không đổi được token: \(error)"
        }
    }

    private func start() async {
        guard status == .stopped || isFailed else { return }
        do {
            _ = try tokenStore.loadOrCreate()
            let port = port
            let store = tokenStore
            let server = McpServer(
                requestGuard: RequestGuard(port: port, token: { store.cachedToken }),
                registry: ToolRegistry(handlers: ["xdesk_status": StatusTool(snapshot: { [host] in await host.agentSnapshot() })]),
                audit: AuditLog(directory: Self.auditDirectory),
                serverVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0")
            try await listener.start(port: port, server: server)
            status = .running(port: port)
            log.notice("MCP đang nghe 127.0.0.1:\(port, privacy: .public)")
        } catch {
            status = .failed("\(error)")
            log.error("Không bật được MCP: \(String(describing: error), privacy: .public)")
        }
    }

    private func stop() {
        listener.stop()
        status = .stopped
        notice = nil
    }

    private var isFailed: Bool { if case .failed = status { true } else { false } }

    private static var auditDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Xdesk/mcp-audit", isDirectory: true)
    }

    #if DEBUG
    /// Chỉ Debug: ghi token ra tệp 0600 để script curl kiểm thử, token không đi qua log.
    func writeTokenForAutomation(to path: String) {
        guard let token = tokenStore.cachedToken,
              FileManager.default.createFile(atPath: path, contents: Data(token.utf8), attributes: [.posixPermissions: 0o600])
        else { log.error("Không ghi được tệp token tự động hoá"); return }
    }
    #endif
}

extension HostController {
    func agentSnapshot() -> HostSnapshot {
        HostSnapshot(isSharing: isHosting, viewerCount: activeViewerCount, encryptionOn: AppSecurity.current == .encrypted)
    }
}
