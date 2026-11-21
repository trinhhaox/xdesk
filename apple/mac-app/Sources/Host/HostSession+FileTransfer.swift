import Foundation
import os
import XdeskWire

struct ActiveFileTransfer: Sendable {
    let fileName: String
    let fileURL: URL
    let fileHandle: FileHandle
    var receivedChunks: UInt32 = 0
}

extension HostSession {
    private static let transferLog = Logger(subsystem: "vn.xox.xdesk", category: "file-transfer")

    private static var downloadsDirectory: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        let xdeskDir = downloads.appendingPathComponent("Xdesk")
        try? FileManager.default.createDirectory(at: xdeskDir, withIntermediateDirectories: true)
        return xdeskDir
    }

    func handleFileOffer(_ offer: FileOffer) async {
        guard permissions.input else { return }
        let cleanName = (offer.name as NSString).lastPathComponent
        let targetURL = Self.downloadsDirectory.appendingPathComponent(cleanName)
        
        FileManager.default.createFile(atPath: targetURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: targetURL) else {
            Self.transferLog.error("Không thể mở file để ghi: \(targetURL.path, privacy: .public)")
            return
        }

        fileTransfers[cleanName] = ActiveFileTransfer(
            fileName: cleanName,
            fileURL: targetURL,
            fileHandle: handle
        )
        Self.transferLog.notice("Bắt đầu nhận tệp: \(cleanName, privacy: .public) (\(offer.size) bytes)")
    }

    func handleFileData(_ chunk: FileData) async {
        let cleanName = (chunk.name as NSString).lastPathComponent
        guard permissions.input, var transfer = fileTransfers[cleanName] else { return }
        guard let data = Data(base64Encoded: chunk.chunk) else { return }

        do {
            try transfer.fileHandle.seekToEnd()
            try transfer.fileHandle.write(contentsOf: data)
            transfer.receivedChunks += 1
            fileTransfers[cleanName] = transfer

            if chunk.isLast {
                try? transfer.fileHandle.close()
                fileTransfers.removeValue(forKey: cleanName)
                Self.transferLog.notice("Đã nhận xong tệp: \(transfer.fileName, privacy: .public) tại \(transfer.fileURL.path, privacy: .public)")
            }
        } catch {
            Self.transferLog.error("Lỗi ghi dữ liệu tệp: \(error.localizedDescription, privacy: .public)")
        }
    }
}
