import Foundation
import XdeskWire

/// Ghép lại một lần truyền clipboard: `clip.data` rồi các chunk bulk. Chỉ giữ một lần truyền tại một thời điểm;
/// header mới thay lần dở dang. Chunk thừa/hash sai/định dạng sai → lỗi và bỏ lần truyền.
struct ClipboardReceiver {
    enum Failure: Error, Equatable {
        case unexpectedChunk
        case sizeExceeded
        case hashMismatch
        case malformedItem
    }

    private var header: ClipData?
    private var buffer: [UInt8] = []

    var isReceiving: Bool { header != nil }

    mutating func begin(_ header: ClipData) {
        self.header = header
        buffer = []
        buffer.reserveCapacity(Int(header.size))
    }

    mutating func reset() {
        header = nil
        buffer = []
    }

    /// Nạp một chunk; trả mục hoàn chỉnh khi đủ `size` byte.
    mutating func append(_ chunk: [UInt8]) throws -> ClipboardItem? {
        guard let header else { throw Failure.unexpectedChunk }
        guard buffer.count + chunk.count <= Int(header.size) else { reset(); throw Failure.sizeExceeded }
        buffer += chunk
        guard buffer.count == Int(header.size) else { return nil }
        defer { reset() }
        guard let item = ClipboardItem(kind: header.kind, data: buffer) else { throw Failure.malformedItem }
        guard item.hash == header.hash else { throw Failure.hashMismatch }
        return item
    }
}
