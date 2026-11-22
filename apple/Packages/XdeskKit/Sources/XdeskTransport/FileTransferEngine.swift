import CryptoKit
import Foundation
import os
import XdeskWire

public enum FileTransferDirection: Sendable, Equatable {
    case sending
    case receiving
}

public struct FileTransferProgress: Sendable, Equatable, Identifiable {
    public let id: String
    public let fileName: String
    public let direction: FileTransferDirection
    public let transferredBytes: UInt64
    public let totalBytes: UInt64

    public var fraction: Double {
        totalBytes == 0 ? 1.0 : min(1.0, Double(transferredBytes) / Double(totalBytes))
    }

    public init(id: String, fileName: String, direction: FileTransferDirection, transferredBytes: UInt64, totalBytes: UInt64) {
        self.id = id
        self.fileName = fileName
        self.direction = direction
        self.transferredBytes = transferredBytes
        self.totalBytes = totalBytes
    }
}

public struct FileTransferCompletion: Sendable, Equatable {
    public let id: String
    public let fileName: String
    public let url: URL
    public let size: UInt64

    public init(id: String, fileName: String, url: URL, size: UInt64) {
        self.id = id
        self.fileName = fileName
        self.url = url
        self.size = size
    }
}

public enum FileTransferNaming {
    /// Chỉ lấy tên tệp an toàn (loại bỏ đường dẫn thư mục, ký tự rỗng, `.` / `..`).
    public static func sanitizedName(_ raw: String) -> String {
        let normalized = raw.replacingOccurrences(of: "\\", with: "/")
        let last = normalized.split(separator: "/").last.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if last.isEmpty || last == "." || last == ".." { return "file" }
        return last
    }

    /// Tạo đường dẫn không ghi đè nếu tệp đã tồn tại (`name (1).ext`, `name (2).ext`, …).
    public static func uniqueURL(directory: URL, preferredName: String, fileManager: FileManager = .default) -> URL {
        let clean = sanitizedName(preferredName)
        let candidate = directory.appendingPathComponent(clean)
        if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        let ext = candidate.pathExtension
        let stem = ext.isEmpty ? clean : String(clean.dropLast(ext.count + 1))
        for idx in 1...10_000 {
            let indexed = ext.isEmpty ? "\(stem) (\(idx))" : "\(stem) (\(idx)).\(ext)"
            let next = directory.appendingPathComponent(indexed)
            if !fileManager.fileExists(atPath: next.path) { return next }
        }
        return directory.appendingPathComponent("\(UUID().uuidString)-\(clean)")
    }

    public static func sha256Hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Host từ chối truyền tệp vì thiết bị không (còn) có quyền: gửi `file.cancel` với `reason` này.
public enum FileTransferDenial {
    public static let reason = "permission"
    /// Host không còn hỗ trợ đường `file.offer`/`file.data` cũ.
    public static let unsupportedReason = "unsupported"
    public static let message = "Mac chưa cho phép thiết bị này gửi/nhận tệp. Hãy bật \"Gửi/nhận tệp\" trong Xdesk trên Mac, tab Thiết bị."
}

/// Bộ nhận tệp streaming qua `file.start` + `[file.chunk, BULK]` + `file.done` (không giữ tệp trong RAM).
public actor FileTransferReceiver {
    private struct Active {
        let id: String
        let fileName: String
        let totalBytes: UInt64
        let partURL: URL
        var handle: FileHandle?
        var hasher: SHA256
        var receivedBytes: UInt64 = 0
    }

    private let directoryProvider: @Sendable () -> URL
    private let onProgress: @Sendable (FileTransferProgress?) -> Void
    private let onCompleted: @Sendable (FileTransferCompletion) -> Void
    private let onFailed: @Sendable (String, String) -> Void
    private let log = Logger(subsystem: "vn.xox.xdesk", category: "file-transfer")
    private var transfers: [String: Active] = [:]
    private var pendingBulk: (id: String, expectedSize: UInt32)?

    public init(
        directory: @escaping @Sendable () -> URL,
        onProgress: @escaping @Sendable (FileTransferProgress?) -> Void = { _ in },
        onCompleted: @escaping @Sendable (FileTransferCompletion) -> Void = { _ in },
        onFailed: @escaping @Sendable (String, String) -> Void = { _, _ in }
    ) {
        self.directoryProvider = directory
        self.onProgress = onProgress
        self.onCompleted = onCompleted
        self.onFailed = onFailed
    }

    public func handleStart(_ start: FileStart) {
        guard start.size <= FileTransferLimits.maxBytes else {
            onFailed(FileTransferNaming.sanitizedName(start.name), "Tệp vượt quá giới hạn 2 GB")
            return
        }
        if let existing = transfers.removeValue(forKey: start.id) {
            try? existing.handle?.close()
            try? FileManager.default.removeItem(at: existing.partURL)
        }
        let dir = directoryProvider()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = FileTransferNaming.sanitizedName(start.name)
        let partURL = dir.appendingPathComponent(".xdesk-\(UUID().uuidString).part")
        FileManager.default.createFile(atPath: partURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: partURL) else {
            try? FileManager.default.removeItem(at: partURL)
            onFailed(name, "Không tạo được tệp tạm")
            return
        }
        transfers[start.id] = Active(id: start.id, fileName: name, totalBytes: start.size, partURL: partURL, handle: handle, hasher: SHA256())
        onProgress(FileTransferProgress(id: start.id, fileName: name, direction: .receiving, transferredBytes: 0, totalBytes: start.size))
    }

    public func handleChunkHeader(_ chunk: FileChunk) {
        guard transfers[chunk.id] != nil else {
            pendingBulk = nil
            return
        }
        pendingBulk = (chunk.id, chunk.size)
    }

    /// Nạp 1 frame `BULK` nếu trước đó vừa nhận `file.chunk`. Trả `true` nếu đã tiêu thụ cho file transfer.
    public func handleBulk(_ bytes: [UInt8]) -> Bool {
        guard let pending = pendingBulk else { return false }
        pendingBulk = nil
        guard var active = transfers[pending.id] else { return true }
        guard bytes.count == Int(pending.expectedSize),
              active.receivedBytes + UInt64(bytes.count) <= active.totalBytes,
              let handle = active.handle else {
            cleanup(id: pending.id, notifyError: "Dữ liệu tệp không khớp kích thước")
            return true
        }
        do {
            try handle.write(contentsOf: Data(bytes))
            active.hasher.update(data: bytes)
            active.receivedBytes += UInt64(bytes.count)
            transfers[pending.id] = active
            onProgress(FileTransferProgress(
                id: active.id, fileName: active.fileName, direction: .receiving,
                transferredBytes: active.receivedBytes, totalBytes: active.totalBytes
            ))
        } catch {
            cleanup(id: pending.id, notifyError: "Lỗi ghi tệp: \(error.localizedDescription)")
        }
        return true
    }

    public func handleDone(_ done: FileDone) {
        if pendingBulk?.id == done.id { pendingBulk = nil }
        guard var active = transfers.removeValue(forKey: done.id) else { return }
        try? active.handle?.close()
        active.handle = nil
        let actualHash = FileTransferNaming.sha256Hex(active.hasher.finalize())
        guard active.receivedBytes == active.totalBytes, actualHash == done.hash else {
            try? FileManager.default.removeItem(at: active.partURL)
            onProgress(nil)
            onFailed(active.fileName, "Tệp bị hỏng hoặc chưa đủ dữ liệu (sai SHA-256)")
            return
        }
        let targetURL = FileTransferNaming.uniqueURL(directory: directoryProvider(), preferredName: active.fileName)
        do {
            try FileManager.default.moveItem(at: active.partURL, to: targetURL)
            onProgress(nil)
            onCompleted(FileTransferCompletion(id: active.id, fileName: targetURL.lastPathComponent, url: targetURL, size: active.totalBytes))
            log.notice("nhận xong tệp \(targetURL.lastPathComponent, privacy: .public) (\(active.totalBytes) B)")
        } catch {
            try? FileManager.default.removeItem(at: active.partURL)
            onProgress(nil)
            onFailed(active.fileName, "Không lưu được tệp: \(error.localizedDescription)")
        }
    }

    public func handleCancel(_ cancel: FileCancel) {
        if pendingBulk?.id == cancel.id { pendingBulk = nil }
        cleanup(id: cancel.id, notifyError: nil)
    }

    public var hasActiveTransfers: Bool { !transfers.isEmpty }

    /// Huỷ mọi tệp đang nhận (xoá tệp tạm); trả về id đã huỷ để bên gọi báo cho đối tác.
    @discardableResult
    public func cancelAll() -> [String] {
        pendingBulk = nil
        let ids = Array(transfers.keys)
        for key in ids {
            cleanup(id: key, notifyError: nil)
        }
        return ids
    }

    private func cleanup(id: String, notifyError: String?) {
        guard let active = transfers.removeValue(forKey: id) else { return }
        try? active.handle?.close()
        try? FileManager.default.removeItem(at: active.partURL)
        onProgress(nil)
        if let notifyError { onFailed(active.fileName, notifyError) }
    }
}

/// Bộ gửi tệp streaming từng mảnh 64 KiB từ đĩa qua kênh điều khiển.
public enum FileTransferSender {
    public static func sendFile(
        id: String = UUID().uuidString,
        url: URL,
        connection: ControlConnection,
        isCancelled: @escaping @Sendable () async -> Bool = { false },
        cancelReason: @escaping @Sendable () -> String = { "cancelled" },
        onProgress: @escaping @Sendable (FileTransferProgress?) -> Void = { _ in }
    ) async throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let totalBytes = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        guard totalBytes <= FileTransferLimits.maxBytes else {
            throw WireError.invalidField("file.start.size")
        }
        let fileName = FileTransferNaming.sanitizedName(url.lastPathComponent)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        _ = try await connection.send(.fileStart(FileStart(id: id, name: fileName, size: totalBytes)))
        onProgress(FileTransferProgress(id: id, fileName: fileName, direction: .sending, transferredBytes: 0, totalBytes: totalBytes))

        var hasher = SHA256()
        var sentBytes: UInt64 = 0
        while let data = try handle.read(upToCount: FileTransferLimits.chunkBytes), !data.isEmpty {
            if await isCancelled() {
                _ = try? await connection.send(.fileCancel(FileCancel(id: id, reason: cancelReason())))
                onProgress(nil)
                throw CancellationError()
            }
            let bytes = [UInt8](data)
            hasher.update(data: data)
            try await connection.sendFileBulkChunk(FileChunk(id: id, size: UInt32(bytes.count)), payload: bytes)
            sentBytes += UInt64(bytes.count)
            onProgress(FileTransferProgress(id: id, fileName: fileName, direction: .sending, transferredBytes: sentBytes, totalBytes: totalBytes))
        }
        let hash = FileTransferNaming.sha256Hex(hasher.finalize())
        _ = try await connection.send(.fileDone(FileDone(id: id, hash: hash)))
        onProgress(nil)
    }
}
