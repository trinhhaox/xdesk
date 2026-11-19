import XdeskClipboard
import XdeskTransport
import XdeskWire

extension ViewerSession {
    /// Khả năng viewer đưa ra: `.clipboard` chỉ khi app có cấu hình clipboard; host chỉ giữ lại nếu thiết bị này được cấp quyền.
    var offeredCaps: Capabilities { clipboardConfig == nil ? [.h264, .hevc] : [.h264, .hevc, .clipboard] }

    func startClipboard(on connection: ControlConnection, negotiated: Capabilities) async {
        guard negotiated.contains(.clipboard), let config = clipboardConfig else { return }
        let sync = ClipboardSync(transport: connection, pasteboard: config.pasteboard, isEnabled: { true })
        clipboardSync = sync
        clipboardAvailable = true
        if config.autoWatch { await sync.startWatching() }
    }

    func stopClipboard() async {
        await clipboardSync?.stop()
        clipboardSync = nil
        clipboardAvailable = false
    }

    /// Gửi clipboard hiện tại sang Mac (nút "Gửi clipboard sang Mac" trên iOS). `.disabled` khi host chưa cấp quyền clipboard.
    public func sendClipboard() async -> ClipboardSync.SendOutcome {
        guard let clipboardSync else { return .disabled }
        return await clipboardSync.sendCurrent()
    }
}
