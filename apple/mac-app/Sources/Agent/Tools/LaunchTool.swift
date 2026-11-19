import AppKit
import Foundation
import XdeskAgent

/// Mở app (bundle id) hoặc URL rồi dời các cửa sổ MỚI của app đó lên màn hình agent. Cửa sổ có sẵn của người dùng không bị đụng tới.
struct LaunchTool: ToolHandler {
    let runtime: AgentRuntime

    func call(arguments: JsonValue) async -> ToolResult {
        guard let target = arguments["target"]?.stringValue, !target.isEmpty else { return .error("Thiếu target") }
        guard case .success(let context) = await runtime.requireDisplay() else { return .error("Chưa có màn hình agent.") }
        let resolved: (appURL: URL, url: URL?)
        switch resolve(target) {
        case .failure(let failure): return .error(failure.message, audit: "refused")
        case .success(let value): resolved = value
        }
        guard let bundle = Bundle(url: resolved.appURL), let bundleId = bundle.bundleIdentifier else { return .error("Không đọc được bundle id của app") }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? bundleId
        if case .refused(let reason) = await runtime.gate.evaluate(bundleId: bundleId, displayName: name) { return .error(reason, audit: "refused") }
        guard AccessibilityPermission.isGranted else { return .error("Thiếu quyền Trợ năng để đưa cửa sổ lên màn hình agent. \(AccessibilityPermission.guidance)") }
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
        let before = existing.map { WindowMover.windows(of: $0.processIdentifier) } ?? []
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let app: NSRunningApplication
        do {
            if let url = resolved.url { app = try await NSWorkspace.shared.open([url], withApplicationAt: resolved.appURL, configuration: configuration) }
            else { app = try await NSWorkspace.shared.openApplication(at: resolved.appURL, configuration: configuration) }
        } catch { return .error("Không mở được \(name): \(error.localizedDescription)") }
        let pid = app.processIdentifier
        let origin = context.bounds.origin
        let size = context.bounds.size
        let moved = await Task.detached { await WindowMover.moveNewWindows(pid: pid, excluding: before, to: origin, within: size) }.value
        if moved == 0 {
            return .ok("Đã mở \(name) nhưng chưa có cửa sổ mới nào được đưa lên màn hình agent (app có thể đã chạy sẵn). Dùng xdesk_press_keys [\"cmd\",\"n\"] sau khi focus app trên màn hình agent, rồi xdesk_screenshot để kiểm tra.")
        }
        return .ok("Đã mở \(name) và đưa \(moved) cửa sổ lên màn hình agent. Hãy xdesk_screenshot để xem.")
    }

    private func resolve(_ target: String) -> Result<(appURL: URL, url: URL?), AgentToolFailure> {
        if let url = URL(string: target), let scheme = url.scheme, !scheme.isEmpty, target.contains(":") {
            if AppPolicy.isSystemSettingsURL(url) { return .failure(AgentToolFailure("luật app: Cài đặt hệ thống (mục Quyền riêng tư) bị cấm (never)")) }
            guard ["http", "https", "file"].contains(scheme.lowercased()) else { return .failure(AgentToolFailure("Chỉ mở URL http/https/file")) }
            guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else { return .failure(AgentToolFailure("Không có app mở được URL này")) }
            return .success((appURL, url))
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) else {
            return .failure(AgentToolFailure("Không tìm thấy app với bundle id \(target)"))
        }
        return .success((appURL, nil))
    }
}
