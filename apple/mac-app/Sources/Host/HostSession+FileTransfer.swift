import Foundation
import os
import XdeskTransport
import XdeskWire

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
        // Frame BULK ngay sau `file.chunk` luôn thuộc về truyền tệp (kể cả khi bị từ chối/huỷ): nhận hoặc bỏ, không đẩy sang clipboard.
        if expectingFileBulk {
            expectingFileBulk = false
            _ = await fileReceiver.handleBulk(chunk)
            return
        }
        await clipboard?.handleBulk(chunk)
    }

    func handleFileStart(_ start: FileStart) async {
        guard await refreshFileTransferAllowed() else {
            await denyFileTransfer(id: start.id, name: start.name)
            return
        }
        await fileReceiver.handleStart(start)
    }

    /// Mỗi mảnh đọc cờ đồng bộ (watcher làm mới mỗi 0,5 s) để không tốn một lần nhảy actor cho mỗi 64 KiB.
    func handleFileChunk(_ header: FileChunk) async {
        expectingFileBulk = true
        guard negotiatedCaps.contains(.fileTransfer), fileGate.allowed else {
            await denyFileTransfer(id: header.id, name: nil)
            return
        }
        await fileReceiver.handleChunkHeader(header)
    }

    func handleFileDone(_ done: FileDone) async {
        guard await refreshFileTransferAllowed() else {
            await denyFileTransfer(id: done.id, name: nil)
            return
        }
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
        let fileName = FileTransferNaming.sanitizedName(url.lastPathComponent)
        guard await refreshFileTransferAllowed() else {
            onFileFailed(fileName, Self.fileDeniedLocalMessage)
            return
        }
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
                cancelReason: { [fileGate] in fileGate.allowed ? "cancelled" : FileTransferDenial.reason },
                onProgress: onTransferProgress
            )
        } catch is CancellationError {
            onTransferProgress(nil)
        } catch {
            onTransferProgress(nil)
            onFileFailed(fileName, error.localizedDescription)
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

    // MARK: Đường `file.offer` / `file.data` (Base64) cũ — đã bỏ

    /// Không client nào còn gửi `file.offer`; trả lý do rõ ràng thay vì nhận tệp.
    func handleLegacyFileOffer(_ offer: FileOffer) async {
        _ = try? await connection.send(.fileCancel(FileCancel(id: offer.name, reason: FileTransferDenial.unsupportedReason)))
        log.notice("Từ chối file.offer (đường cũ không còn được hỗ trợ)")
    }
}
