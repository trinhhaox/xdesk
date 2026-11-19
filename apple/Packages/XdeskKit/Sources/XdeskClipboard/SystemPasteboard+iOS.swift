#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
import XdeskWire

/// `UIPasteboard.general`. Chỉ đọc khi người dùng chủ động (nút "Gửi clipboard sang Mac") để tránh banner "đã dán từ".
/// `@unchecked Sendable`: UIPasteboard an toàn khi gọi từ luồng nền, lớp này không giữ trạng thái khả biến.
public final class SystemPasteboard: PasteboardAccess, @unchecked Sendable {
    public init() {}

    public var changeCount: Int { UIPasteboard.general.changeCount }

    public func read() -> ClipboardItem? {
        let board = UIPasteboard.general
        guard ClipboardPolicy.refusalReason(types: board.types) == nil else { return nil }
        if board.hasStrings, let text = board.string, let item = ClipboardItem(text: text) { return item }
        if board.hasImages, let png = board.image?.pngData() { return ClipboardItem(kind: .image, data: [UInt8](png)) }
        return nil
    }

    public func write(_ item: ClipboardItem) -> Int {
        let board = UIPasteboard.general
        switch item.kind {
        case .text: board.string = item.text
        case .image: board.setData(Data(item.data), forPasteboardType: UTType.png.identifier)
        }
        return board.changeCount
    }
}
#endif
