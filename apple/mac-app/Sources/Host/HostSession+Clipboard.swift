import XdeskClipboard
import XdeskCrypto
import XdeskWire

extension HostSession {
    /// Khả năng host đưa ra khi bắt tay: `.clipboard` chỉ khi thiết bị được cấp quyền clipboard (mặc định tắt) và có clipboard để dùng;
    /// audio chỉ khi được cấp quyền âm thanh (mặc định tắt); `.fileTransfer` chỉ khi được cấp quyền gửi/nhận tệp (mặc định tắt); `.mediaOverTcp` chỉ cho đường hầm USB.
    var negotiableCaps: Capabilities {
        var caps = hostCaps.union([.hotReconfigure, .videoPause, .mediaKeys, .multiDisplay])
        if permissions.fileTransfer { caps.insert(.fileTransfer) }
        if pasteboard != nil, permissions.clipboard { caps.insert(.clipboard) }
        if permissions.audio { caps.formUnion([.audioPCM, .audioAACELD]) }
        if permissions.unlock, remoteUnlockSettingSnapshot { caps.insert(.remoteUnlock) }
        if connection.isUsbTunnel || connection.isLoopback { caps.insert(.mediaOverTcp) }
        return caps
    }

    /// Bật đồng bộ clipboard cho phiên này. Quyền được kiểm lại mỗi lần (tắt giữa phiên → ngừng gửi/nhận ngay).
    func startClipboard() async {
        guard let pasteboard else { return }
        let key = await connection.peer?.publicKey
        let snapshot = permissions
        let lookup = permissionLookup
        let sync = ClipboardSync(transport: connection, pasteboard: pasteboard, isEnabled: {
            let live = if let key { await lookup(key) } else { nil as DevicePermissions? }
            return LivePermissions.resolve(peerKey: key, live: live, snapshot: snapshot).clipboard
        })
        clipboard = sync
        await sync.startWatching()
    }
}
