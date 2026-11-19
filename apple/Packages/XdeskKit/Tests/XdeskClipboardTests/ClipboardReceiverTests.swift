import Foundation
import Testing
@testable import XdeskClipboard
import XdeskWire

@Suite struct ClipboardReceiverTests {
    private func header(for item: ClipboardItem, hash: String? = nil) -> ClipData {
        ClipData(kind: item.kind, size: item.size, hash: hash ?? item.hash)
    }

    @Test func rebuildsFromChunks() throws {
        let item = png(extraBytes: 150_000)
        var receiver = ClipboardReceiver()
        receiver.begin(header(for: item))
        let mid = item.data.count / 2
        #expect(try receiver.append(Array(item.data[..<mid])) == nil)
        #expect(try receiver.append(Array(item.data[mid...])) == item)
        #expect(!receiver.isReceiving)
    }

    @Test func chunkWithoutHeaderIsRejected() {
        var receiver = ClipboardReceiver()
        #expect(throws: ClipboardReceiver.Failure.unexpectedChunk) { _ = try receiver.append([1]) }
    }

    @Test func extraBytesAbortTransfer() {
        var receiver = ClipboardReceiver()
        receiver.begin(ClipData(kind: .text, size: 2, hash: String(repeating: "a", count: 64)))
        #expect(throws: ClipboardReceiver.Failure.sizeExceeded) { _ = try receiver.append([65, 66, 67]) }
        #expect(!receiver.isReceiving)
    }

    @Test func wrongHashIsRejected() {
        let item = text("dữ liệu")
        var receiver = ClipboardReceiver()
        receiver.begin(header(for: item, hash: String(repeating: "0", count: 64)))
        #expect(throws: ClipboardReceiver.Failure.hashMismatch) { _ = try receiver.append(item.data) }
    }

    @Test func nonPngImageIsRejected() {
        var receiver = ClipboardReceiver()
        receiver.begin(ClipData(kind: .image, size: 3, hash: String(repeating: "0", count: 64)))
        #expect(throws: ClipboardReceiver.Failure.malformedItem) { _ = try receiver.append([1, 2, 3]) }
    }

    @Test func newHeaderReplacesPartialTransfer() throws {
        var receiver = ClipboardReceiver()
        receiver.begin(ClipData(kind: .text, size: 10, hash: String(repeating: "0", count: 64)))
        _ = try receiver.append([65])
        let item = text("mới")
        receiver.begin(header(for: item))
        #expect(try receiver.append(item.data) == item)
    }
}
