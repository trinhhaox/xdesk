import XdeskTransport
import XdeskWire

/// Đường gửi của `ClipboardSync`: kênh control đã mã hoá (hoặc bản giả trong test).
public protocol ClipboardTransport: Sendable {
    func sendClip(_ message: ControlMessage) async throws
    func sendClipData(_ header: ClipData, payload: [UInt8]) async throws
}

extension ControlConnection: ClipboardTransport {
    public func sendClip(_ message: ControlMessage) async throws { try await send(message) }
}

/// Cấu hình clipboard của một viewer: dùng clipboard nào và có tự theo dõi thay đổi không
/// (Mac: tự theo dõi; iOS: chỉ gửi khi người dùng bấm nút để tránh banner "đã dán từ").
public struct ClipboardConfig: Sendable {
    public let pasteboard: any PasteboardAccess
    public let autoWatch: Bool

    public init(pasteboard: any PasteboardAccess, autoWatch: Bool) {
        self.pasteboard = pasteboard
        self.autoWatch = autoWatch
    }
}
