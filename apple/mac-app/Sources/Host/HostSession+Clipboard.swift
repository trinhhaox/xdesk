import XdeskClipboard
import XdeskCrypto
import XdeskWire

extension HostSession {
    /// Khả năng host đưa ra khi bắt tay: chỉ có `.clipboard` khi thiết bị đã được cấp quyền clipboard (mặc định tắt) và có clipboard để dùng.
    var negotiableCaps: Capabilities {
        pasteboard != nil && permissions.clipboard ? hostCaps.union(.clipboard) : hostCaps
    }

    /// Bật đồng bộ clipboard cho phiên này. Quyền được kiểm lại mỗi lần (tắt giữa phiên → ngừng gửi/nhận ngay).
    func startClipboard() async {
        guard let pasteboard else { return }
        let key = await connection.peer?.publicKey
        let snapshot = permissions.clipboard
        let lookup = permissionLookup
        let sync = ClipboardSync(transport: connection, pasteboard: pasteboard, isEnabled: {
            guard let key, let live = await lookup(key) else { return snapshot }
            return live.clipboard
        })
        clipboard = sync
        await sync.startWatching()
    }
}
