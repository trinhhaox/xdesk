import Foundation
import os
import XdeskTransport
import XdeskWire

struct ActiveFileTransfer: Sendable {
    let fileName: String
    let fileURL: URL
    let fileHandle: FileHandle
    var receivedChunks: UInt32 = 0
}

extension HostSession {
    private static let transferLog = Logger(subsystem: "vn.xox.xdesk", category: "file-transfer")

    static var downloadsDirectory: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        let xdeskDir = downloads.appendingPathComponent("Xdesk", isDirectory: true)
        try? FileManager.default.createDirectory(at: xdeskDir, withIntermediateDirectories: true)
        return xdeskDir
    }

    // MARK: Streaming BULK 2 chiều

    func handleIncomingBulk(_ chunk: [UInt8]) async {
        if await fileReceiver.handleBulk(chunk) { return }
        await clipboard?.handleBulk(chunk)
    }

    func handleFileStart(_ start: FileStart) async {
        guard permissions.input else { return }
        await fileReceiver.handleStart(start)
    }

    func handleFileChunk(_ header: FileChunk) async {
        guard permissions.input else { return }
        await fileReceiver.handleChunkHeader(header)
    }

    func handleFileDone(_ done: FileDone) async {
        guard permissions.input else { return }
        await fileReceiver.handleDone(done)
    }

    func handleFileCancel(_ cancel: FileCancel) async {
        if activeSendingFileId == cancel.id {
            fileCancelToken.cancel(cancel.id)
        } else {
            await fileReceiver.handleCancel(cancel)
        }
    }

    func sendFileToViewer(url: URL) async {
        guard permissions.input else { return }
        let transferId = UUID().uuidString
        activeSendingFileId = transferId
        defer {
            activeSendingFileId = nil
            fileCancelToken.clear(transferId)
        }
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try await FileTransferSender.sendFile(
                id: transferId,
                url: url,
                connection: connection,
                isCancelled: { [fileCancelToken] in fileCancelToken.isCancelled(transferId) },
                onProgress: onTransferProgress
            )
        } catch is CancellationError {
            onTransferProgress(nil)
        } catch {
            onTransferProgress(nil)
            onFileFailed(FileTransferNaming.sanitizedName(url.lastPathComponent), error.localizedDescription)
            Self.transferLog.error("Gửi tệp sang viewer lỗi: \(error.localizedDescription, privacy: .public)")
        }
    }

    func cancelActiveFileTransfer() async {
        if let sendingId = activeSendingFileId {
            fileCancelToken.cancel(sendingId)
            return
        }
        await fileReceiver.cancelAll()
        onTransferProgress(nil)
    }

    // MARK: Tương thích ngược client cũ (`file.offer` / `file.data` Base64)

    func handleFileOffer(_ offer: FileOffer) async {
        guard permissions.input else { return }
        let cleanName = FileTransferNaming.sanitizedName(offer.name)
        let targetURL = FileTransferNaming.uniqueURL(directory: Self.downloadsDirectory, preferredName: cleanName)

        FileManager.default.createFile(atPath: targetURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: targetURL) else {
            Self.transferLog.error("Không thể mở file để ghi: \(targetURL.path, privacy: .public)")
            return
        }

        fileTransfers[cleanName] = ActiveFileTransfer(
            fileName: targetURL.lastPathComponent,
            fileURL: targetURL,
            fileHandle: handle
        )
        Self.transferLog.notice("Bắt đầu nhận tệp (legacy): \(targetURL.lastPathComponent, privacy: .public) (\(offer.size) bytes)")
    }

    func handleFileData(_ chunk: FileData) async {
        let cleanName = FileTransferNaming.sanitizedName(chunk.name)
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
                onFileReceived(FileTransferCompletion(
                    id: cleanName,
                    fileName: transfer.fileName,
                    url: transfer.fileURL,
                    size: (try? FileManager.default.attributesOfItem(atPath: transfer.fileURL.path)[.size] as? NSNumber)?.uint64Value ?? 0
                ))
                Self.transferLog.notice("Đã nhận xong tệp: \(transfer.fileName, privacy: .public) tại \(transfer.fileURL.path, privacy: .public)")
            }
        } catch {
            Self.transferLog.error("Lỗi ghi dữ liệu tệp: \(error.localizedDescription, privacy: .public)")
        }
    }
}
