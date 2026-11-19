import Foundation
@testable import XdeskClipboard
import XdeskWire

/// Clipboard giả trong bộ nhớ; áp `ClipboardPolicy` như bản thật.
final class FakePasteboard: PasteboardAccess, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var content: ClipboardItem?
    private var types: [String] = []

    var changeCount: Int { lock.withLock { count } }

    /// Giả lập người dùng sao chép ở app khác.
    func copy(_ item: ClipboardItem, types: [String] = []) {
        lock.withLock { content = item; self.types = types; count += 1 }
    }

    func read() -> ClipboardItem? {
        lock.withLock { ClipboardPolicy.refusalReason(types: types) == nil ? content : nil }
    }

    func write(_ item: ClipboardItem) -> Int {
        lock.withLock { content = item; types = []; count += 1; return count }
    }

    var current: ClipboardItem? { lock.withLock { content } }
}

/// Nối hai `ClipboardSync`: message gửi đi được đưa thẳng cho bên kia (theo đúng thứ tự gửi).
actor LoopbackTransport: ClipboardTransport {
    private(set) var sent: [ControlMessage] = []
    private var peer: ClipboardSync?

    func connect(to peer: ClipboardSync) { self.peer = peer }

    func sendClip(_ message: ControlMessage) async throws {
        sent.append(message)
        await peer?.handle(message)
    }

    func sendClipData(_ header: ClipData, payload: [UInt8]) async throws {
        sent.append(.clipData(header))
        await peer?.handle(.clipData(header))
        var offset = 0
        while offset < payload.count {
            let end = min(offset + ControlFrame.maxBulkPayload, payload.count)
            await peer?.handleBulk(Array(payload[offset..<end]))
            offset = end
        }
    }

    var sentCount: Int { sent.count }
}

struct Pair {
    let a: ClipboardSync, b: ClipboardSync
    let boardA = FakePasteboard(), boardB = FakePasteboard()
    let toB = LoopbackTransport(), toA = LoopbackTransport()

    init(enabledA: Bool = true, enabledB: Bool = true) async {
        a = ClipboardSync(transport: toB, pasteboard: boardA, isEnabled: { enabledA })
        b = ClipboardSync(transport: toA, pasteboard: boardB, isEnabled: { enabledB })
        await toB.connect(to: b)
        await toA.connect(to: a)
    }
}

func text(_ value: String) -> ClipboardItem {
    guard let item = ClipboardItem(text: value) else { preconditionFailure("văn bản test không hợp lệ") }
    return item
}

func png(extraBytes: Int = 0) -> ClipboardItem {
    let header: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    guard let item = ClipboardItem(kind: .image, data: header + [UInt8](repeating: 7, count: extraBytes)) else {
        preconditionFailure("PNG test không hợp lệ")
    }
    return item
}
