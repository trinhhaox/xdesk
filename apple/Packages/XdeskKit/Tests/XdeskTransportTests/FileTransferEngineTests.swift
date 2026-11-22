import Foundation
import Testing
import XdeskWire
@testable import XdeskTransport

@Suite struct FileTransferEngineTests {
    @Test func namingSanitizesTraversalAndDeduplicatesCollisions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("xdesk-ft-name-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(FileTransferNaming.sanitizedName("../../etc/passwd") == "passwd")
        #expect(FileTransferNaming.sanitizedName("..") == "file")
        #expect(FileTransferNaming.sanitizedName("C:\\Users\\demo\\report.pdf") == "report.pdf")

        let first = FileTransferNaming.uniqueURL(directory: dir, preferredName: "photo.jpg")
        #expect(first.lastPathComponent == "photo.jpg")
        FileManager.default.createFile(atPath: first.path, contents: Data("1".utf8))

        let second = FileTransferNaming.uniqueURL(directory: dir, preferredName: "photo.jpg")
        #expect(second.lastPathComponent == "photo (1).jpg")
        FileManager.default.createFile(atPath: second.path, contents: Data("2".utf8))

        let third = FileTransferNaming.uniqueURL(directory: dir, preferredName: "photo.jpg")
        #expect(third.lastPathComponent == "photo (2).jpg")
    }

    @Test(.timeLimit(.minutes(1))) func streamingMultiChunkFileTransfersIntactOverEncryptedChannel() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("xdesk-ft-recv-\(UUID().uuidString)")
        let srcDir = FileManager.default.temporaryDirectory.appendingPathComponent("xdesk-ft-src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: srcDir)
        }

        let payload = Data((0..<(200 * 1024 + 17)).map { UInt8(truncatingIfNeeded: $0 &* 13 &+ 5) })
        let srcURL = srcDir.appendingPathComponent("sample.bin")
        try payload.write(to: srcURL)

        let completion = LockedCompletion()
        let receiver = FileTransferReceiver(
            directory: { dir },
            onCompleted: { completion.set($0) }
        )

        let rig = try await SecureRig.make()
        let (viewer, host) = try await rig.pairWithQr()

        let readTask = Task {
            while let inbound = try await host.nextInbound() {
                switch inbound {
                case .bulk(let chunk):
                    _ = await receiver.handleBulk(chunk)
                case .message(let env):
                    switch env.message {
                    case .fileStart(let s): await receiver.handleStart(s)
                    case .fileChunk(let c): await receiver.handleChunkHeader(c)
                    case .fileDone(let d):
                        await receiver.handleDone(d)
                        return
                    case .fileCancel(let c):
                        await receiver.handleCancel(c)
                        return
                    default: break
                    }
                default: break
                }
            }
        }

        try await FileTransferSender.sendFile(id: "t-1", url: srcURL, connection: viewer)
        try await readTask.value
        let result = try #require(completion.value)
        #expect(result.fileName == "sample.bin")
        #expect(result.size == UInt64(payload.count))
        #expect(try Data(contentsOf: result.url) == payload)
        await rig.stop()
    }

    @Test func cancelClearsTemporaryPartFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("xdesk-ft-cancel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let receiver = FileTransferReceiver(directory: { dir })
        await receiver.handleStart(FileStart(id: "c1", name: "big.zip", size: 1000))
        await receiver.handleChunkHeader(FileChunk(id: "c1", size: 4))
        let consumed = await receiver.handleBulk([1, 2, 3, 4])
        #expect(consumed)
        await receiver.handleCancel(FileCancel(id: "c1", reason: "user cancelled"))
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.isEmpty)
    }
}

private final class LockedCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: FileTransferCompletion?
    var value: FileTransferCompletion? { lock.withLock { stored } }
    func set(_ next: FileTransferCompletion) { lock.withLock { stored = next } }
}
