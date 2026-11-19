import XdeskClipboard
import XdeskTransport
import XdeskWire

extension ViewerSession {
    /// Khả năng viewer đưa ra: `.clipboard` / audio chỉ khi app có cấu hình tương ứng; host chỉ giữ lại nếu thiết bị này được cấp quyền.
    /// `.mediaOverTcp` chỉ khi đi qua đường hầm USB (không có UDP).
    func offeredCaps(tunnel: Bool) -> Capabilities {
        var caps: Capabilities = [.h264, .hevc]
        if clipboardConfig != nil { caps.insert(.clipboard) }
        if audioConfig != nil { caps.formUnion([.audioPCM, .audioAACELD]) }
        if tunnel { caps.insert(.mediaOverTcp) }
        return caps
    }

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
