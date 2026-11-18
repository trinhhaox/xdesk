import Foundation
import os

public protocol PairedDevicesStorage: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
}

/// File JSON trong Application Support: thư mục 0700, file 0600 ngay từ lúc tạo, ghi nguyên tử (tệp tạm cùng thư mục rồi `rename`).
public struct FilePairedDevicesStorage: PairedDevicesStorage {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static func defaultURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Xdesk", isDirectory: true).appendingPathComponent("paired-devices.json")
    }

    public func read() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func write(_ data: Data) throws {
        let directory = url.deletingLastPathComponent()
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let temporary = directory.appendingPathComponent(".paired-devices-\(UUID().uuidString).tmp")
        guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(temporary.path, url.path) == 0 else {
            let code = errno
            try? manager.removeItem(at: temporary)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }
}

public final class InMemoryPairedDevicesStorage: PairedDevicesStorage {
    private let data = OSAllocatedUnfairLock<Data?>(initialState: nil)

    public init() {}

    public func read() throws -> Data? { data.withLock { $0 } }
    public func write(_ newData: Data) throws { data.withLock { $0 = newData } }
}
