#if canImport(AppKit)
import AppKit
import XdeskWire

/// `NSPasteboard` (mặc định `.general`; Debug có thể truyền tên pasteboard riêng để kiểm thử không đụng clipboard thật).
/// `@unchecked Sendable`: NSPasteboard cho phép truy cập từ luồng nền, lớp này không giữ trạng thái khả biến.
public final class SystemPasteboard: PasteboardAccess, @unchecked Sendable {
    private let board: NSPasteboard

    public init(name: String? = nil) {
        board = name.map { NSPasteboard(name: NSPasteboard.Name($0)) } ?? .general
    }

    public var changeCount: Int { board.changeCount }

    public func read() -> ClipboardItem? {
        let types = (board.types ?? []).map(\.rawValue)
        guard ClipboardPolicy.refusalReason(types: types) == nil else { return nil }
        if let text = board.string(forType: .string), let item = ClipboardItem(text: text) { return item }
        if let png = board.data(forType: .png), let item = ClipboardItem(kind: .image, data: [UInt8](png)) { return item }
        // Ảnh chụp màn hình thường chỉ có TIFF: đổi sang PNG để gửi.
        if let tiff = board.data(forType: .tiff), let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            return ClipboardItem(kind: .image, data: [UInt8](png))
        }
        return nil
    }

    public func write(_ item: ClipboardItem) -> Int {
        board.clearContents()
        switch item.kind {
        case .text: if let text = item.text { board.setString(text, forType: .string) }
        case .image: board.setData(Data(item.data), forType: .png)
        }
        return board.changeCount
    }
}
#endif
