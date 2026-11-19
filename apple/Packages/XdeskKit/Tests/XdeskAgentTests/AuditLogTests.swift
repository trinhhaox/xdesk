import Foundation
import Testing
@testable import XdeskAgent

private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(days: Double) { lock.withLock { current = current.addingTimeInterval(days * 86_400) } }
}

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("xdesk-audit-\(UUID().uuidString)")
}

@Suite struct AuditLogTests {
    @Test func writesOneJsonLinePerRecordWithoutArguments() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = AuditLog(directory: directory)
        log.record(method: "tools/call", tool: "xdesk_type_text", result: "ok", durationMs: 12)
        log.record(method: "tools/list", tool: nil, result: "ok", durationMs: 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.count == 1)
        let lines = try String(contentsOf: directory.appendingPathComponent(files[0]), encoding: .utf8)
            .split(separator: "\n").map { try JSONDecoder().decode(AuditEntry.self, from: Data($0.utf8)) }
        #expect(lines.count == 2)
        #expect(lines[0].tool == "xdesk_type_text")
        #expect(lines[0].durationMs == 12)
        #expect(lines[1].tool == nil)
    }

    @Test func filePermissionsAreOwnerOnly() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        AuditLog(directory: directory).record(method: "ping", tool: nil, result: "ok", durationMs: 0)
        let name = try #require(try FileManager.default.contentsOfDirectory(atPath: directory.path).first)
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
    }

    @Test func rotatesFilesOlderThanSevenDays() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = MutableClock(Date(timeIntervalSince1970: 1_800_000_000))
        let log = AuditLog(directory: directory, now: { clock.now })
        log.record(method: "ping", tool: nil, result: "ok", durationMs: 0)
        let first = try #require(try FileManager.default.contentsOfDirectory(atPath: directory.path).first)
        clock.advance(days: 6)
        log.record(method: "ping", tool: nil, result: "ok", durationMs: 0)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(first).path))
        clock.advance(days: 2)
        log.record(method: "ping", tool: nil, result: "ok", durationMs: 0)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(first).path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
    }

    @Test func serverAuditsToolNameAndResultNeverArguments() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = McpServer(
            requestGuard: RequestGuard(port: 1, token: { "t" }), registry: ToolRegistry(),
            audit: AuditLog(directory: directory), serverVersion: "0")
        let headers = ["host": "127.0.0.1:1", "authorization": "Bearer t"]
        let initialize = HttpRequest(method: "POST", path: "/mcp", headers: headers, body: Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}"#.utf8))
        let session = try #require(await server.handle(initialize).headers["Mcp-Session-Id"])
        let secret = "mat-khau-bi-mat-123"
        let call = HttpRequest(
            method: "POST", path: "/mcp", headers: headers.merging(["mcp-session-id": session]) { $1 },
            body: Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"xdesk_type_text","arguments":{"text":"\#(secret)"}}}"#.utf8))
        _ = await server.handle(call)
        let name = try #require(try FileManager.default.contentsOfDirectory(atPath: directory.path).first)
        let content = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
        #expect(content.contains("xdesk_type_text"))
        #expect(content.contains("tool_error"))
        #expect(!content.contains(secret))
    }
}
