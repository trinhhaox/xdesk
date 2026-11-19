import Foundation
import os

/// Một dòng nhật ký: chỉ method, tên tool, kết quả và thời gian; không bao giờ ghi nội dung tham số.
public struct AuditEntry: Sendable, Equatable, Codable {
    public var timestamp: String
    public var method: String
    public var tool: String?
    public var result: String
    public var durationMs: Int
    public var detail: String?

    enum CodingKeys: String, CodingKey { case timestamp = "ts", method, tool, result, durationMs = "ms", detail }
}

/// JSONL theo ngày (UTC) trong thư mục riêng, xoá tệp cũ hơn `retentionDays`.
public final class AuditLog: Sendable {
    private static let logger = Logger(subsystem: "vn.xox.xdesk", category: "mcp-audit")
    private static let prefix = "mcp-audit-"
    private static let suffix = ".jsonl"

    private let directory: URL
    private let retentionDays: Int
    private let now: @Sendable () -> Date
    private let lastPrunedDay = OSAllocatedUnfairLock<String?>(initialState: nil)
    private let writeLock = OSAllocatedUnfairLock()

    public init(directory: URL, retentionDays: Int = 7, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.retentionDays = retentionDays
        self.now = now
    }

    public func record(method: String, tool: String?, result: String, durationMs: Int, detail: String? = nil) {
        let date = now()
        let entry = AuditEntry(
            timestamp: Self.timestamp(date), method: method, tool: tool, result: result, durationMs: durationMs, detail: detail)
        do {
            var line = try JSONEncoder().encode(entry)
            line.append(0x0A)
            try append(line, to: fileURL(for: Self.day(date)))
            pruneIfNeeded(date)
        } catch {
            Self.logger.error("Không ghi được nhật ký MCP: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func append(_ line: Data, to url: URL) throws {
        try writeLock.withLock {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if !FileManager.default.fileExists(atPath: url.path) {
                guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        }
    }

    private func pruneIfNeeded(_ date: Date) {
        let today = Self.day(date)
        let alreadyPruned = lastPrunedDay.withLock { day in
            defer { day = today }
            return day == today
        }
        guard !alreadyPruned else { return }
        let cutoff = Self.day(date.addingTimeInterval(-Double(retentionDays) * 86_400))
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix(Self.prefix) && name.hasSuffix(Self.suffix) {
            let day = String(name.dropFirst(Self.prefix.count).dropLast(Self.suffix.count))
            // Chuỗi yyyy-MM-dd so sánh theo thứ tự từ điển cũng là thứ tự thời gian.
            guard day < cutoff else { continue }
            do { try FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
            catch { Self.logger.error("Không xoá được nhật ký cũ: \(error.localizedDescription, privacy: .public)") }
        }
    }

    private func fileURL(for day: String) -> URL { directory.appendingPathComponent("\(Self.prefix)\(day)\(Self.suffix)") }

    private static func timestamp(_ date: Date) -> String { date.formatted(.iso8601) }

    static func day(_ date: Date) -> String { String(date.formatted(.iso8601).prefix(10)) }
}
