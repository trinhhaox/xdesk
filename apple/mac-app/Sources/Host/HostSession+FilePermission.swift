import Foundation
import XdeskCrypto
import XdeskTransport
import XdeskWire

/// Cờ quyền truyền tệp đọc đồng bộ từ vòng nhận từng mảnh 64 KiB (không phải nhảy actor/MainActor mỗi mảnh).
/// Được làm mới tại mỗi `file.start`/`file.done`, hành động "Gửi tệp" trên Mac và bởi watcher mỗi 500 ms
/// (suốt phiên có thương lượng `.fileTransfer`), nên tắt quyền giữa phiên có hiệu lực trong khoảng 0,5 giây.
final class HostFileGate: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var allowed: Bool { lock.withLock { value } }
    func set(_ newValue: Bool) { lock.withLock { value = newValue } }
}

/// Quyền "sống" của thiết bị: đã xác thực mà không còn trong danh sách (bị thu hồi/xoá) thì mất mọi quyền (Fail-Closed).
/// Chỉ khi không có peer xác thực (Debug plaintext) mới dùng quyền lúc bắt tay.
enum LivePermissions {
    static let none = DevicePermissions(view: false, input: false, clipboard: false, audio: false)

    static func resolve(peerKey: [UInt8]?, live: DevicePermissions?, snapshot: DevicePermissions) -> DevicePermissions {
        guard peerKey != nil else { return snapshot }
        return live ?? none
    }
}

extension HostSession {
    static let filePermissionPollInterval: Duration = .milliseconds(500)
    private static let denyNoticeInterval: Duration = .seconds(10)

    static var fileDeniedLocalMessage: String {
        String(localized: "Thiết bị này chưa được cấp quyền gửi/nhận tệp. Bật \"Gửi/nhận tệp\" ở tab Thiết bị trong Cài đặt (nếu vừa bật, hãy kết nối lại thiết bị).")
    }

    /// Quyền hiện tại của thiết bị, đọc lại từ danh sách thiết bị đã ghép.
    func livePermissions() async -> DevicePermissions {
        let key = await connection.peer?.publicKey
        let live = if let key { await permissionLookup(key) } else { nil as DevicePermissions? }
        return LivePermissions.resolve(peerKey: key, live: live, snapshot: permissions)
    }

    /// Cho phép truyền tệp khi phiên đã thương lượng `.fileTransfer` và quyền hiện tại còn bật. Cập nhật luôn `fileGate`.
    @discardableResult
    func refreshFileTransferAllowed() async -> Bool {
        let live = await livePermissions()
        let allowed = negotiatedCaps.contains(.fileTransfer) && live.fileTransfer
        fileGate.set(allowed)
        return allowed
    }

    /// Chạy suốt phiên đã thương lượng `.fileTransfer`: quyền bị tắt → huỷ ngay tệp đang truyền và báo cho viewer.
    func startFilePermissionWatch() {
        filePermissionWatch?.cancel()
        filePermissionWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.filePermissionPollInterval)
                guard let self, !Task.isCancelled else { return }
                if await !self.refreshFileTransferAllowed() { await self.revokeActiveFileTransfers() }
            }
        }
    }

    /// Từ chối một `file.*` của viewer: gửi `file.cancel` kèm lý do; thông báo cho người dùng Mac tối đa 1 lần mỗi 10 giây.
    func denyFileTransfer(id: String, name: String?) async {
        await fileReceiver.handleCancel(FileCancel(id: id))
        _ = try? await connection.send(.fileCancel(FileCancel(id: id, reason: FileTransferDenial.reason)))
        let now = ContinuousClock.now
        if let last = lastDenyNoticeAt, now - last < Self.denyNoticeInterval { return }
        lastDenyNoticeAt = now
        let display = name.map(FileTransferNaming.sanitizedName) ?? String(localized: "Tệp")
        onFileFailed(display, String(localized: "Thiết bị chưa được cấp quyền gửi/nhận tệp, đã từ chối."))
        log.notice("Từ chối file.* vì thiết bị không có quyền truyền tệp")
    }

    /// Quyền bị thu hồi: huỷ tệp đang gửi/nhận nếu có. Tệp đang gửi tự phát đúng một `file.cancel` "permission"
    /// (qua `cancelReason`); tệp đang nhận được huỷ và báo ở đây. Chỉ báo lỗi một lần cho mỗi lần thu hồi.
    func revokeActiveFileTransfers() async {
        let sendingId = activeSendingFileId.flatMap { fileCancelToken.isCancelled($0) ? nil : $0 }
        let hasReceiving = await fileReceiver.hasActiveTransfers
        guard sendingId != nil || hasReceiving else { return }
        if let sendingId { fileCancelToken.cancel(sendingId) }
        for id in await fileReceiver.cancelAll() {
            _ = try? await connection.send(.fileCancel(FileCancel(id: id, reason: FileTransferDenial.reason)))
        }
        onTransferProgress(nil)
        onFileFailed(String(localized: "Truyền tệp"), String(localized: "Quyền gửi/nhận tệp đã bị tắt, đã huỷ truyền tệp."))
    }
}
