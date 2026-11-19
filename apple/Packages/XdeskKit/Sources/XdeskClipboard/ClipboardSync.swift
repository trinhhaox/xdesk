import Foundation
import os
import XdeskWire

/// Đồng bộ clipboard hai chiều qua một kênh control đã mã hoá: `clip.offer {kind,size,hash}` → bên kia `clip.pull`
/// → `clip.data` + chunk bulk. Mọi hướng đều qua `isEnabled` (quyền clipboard của thiết bị): tắt thì không gửi, không kéo, không ghi.
/// Chống lặp: sau khi ghi dữ liệu nhận được ta ghi nhớ `changeCount` nên không gửi ngược lại; hash vừa ghi còn được nhớ `echoWindow`
/// (mặc định 3 s) để chặn app thứ ba (trình quản lý clipboard…) chép lại cùng nội dung rồi dội ngược. Quá hạn thì người dùng chép lại
/// đúng nội dung đó vẫn được gửi.
public actor ClipboardSync {
    public enum SendOutcome: Sendable, Equatable {
        case sent(ClipKind)
        case disabled
        /// Clipboard rỗng, chứa mục ẩn (mật khẩu), quá 10 MB hoặc định dạng không hỗ trợ.
        case nothingToSend
        case failed(String)
    }

    public static let pollInterval = Duration.milliseconds(500)

    private let transport: any ClipboardTransport
    private let pasteboard: any PasteboardAccess
    private let isEnabled: @Sendable () async -> Bool
    private let log = Logger(subsystem: "vn.xox.xdesk", category: "clipboard")
    private var offered: [ClipKind: ClipboardItem] = [:]
    private var lastOfferedHash: String?
    private var recentRemote: (hash: String, at: ContinuousClock.Instant)?
    private let echoWindow: Duration
    private var seenChangeCount: Int
    private var receiver = ClipboardReceiver()
    private var watcher: Task<Void, Never>?

    /// Clipboard có sẵn lúc tạo KHÔNG được gửi (chỉ thay đổi sau đó mới gửi).
    public init(
        transport: any ClipboardTransport, pasteboard: any PasteboardAccess, echoWindow: Duration = .seconds(3),
        isEnabled: @escaping @Sendable () async -> Bool
    ) {
        self.echoWindow = echoWindow
        self.transport = transport
        self.pasteboard = pasteboard
        self.isEnabled = isEnabled
        seenChangeCount = pasteboard.changeCount
    }

    // MARK: Theo dõi (Mac)

    /// Thăm dò `changeCount` mỗi 500 ms và tự gửi offer khi đổi.
    public func startWatching() {
        guard watcher == nil else { return }
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                await self?.poll()
            }
        }
    }

    public func stop() {
        watcher?.cancel()
        watcher = nil
        receiver.reset()
    }

    func poll() async {
        let count = pasteboard.changeCount
        guard count != seenChangeCount else { return }
        seenChangeCount = count
        guard await isEnabled(), let item = pasteboard.read() else { return }
        guard !isRecentRemote(item.hash), item.hash != lastOfferedHash else { return }
        _ = await offer(item)
    }

    // MARK: Gửi chủ động (iOS: nút "Gửi clipboard sang Mac")

    public func sendCurrent() async -> SendOutcome {
        guard await isEnabled() else { return .disabled }
        seenChangeCount = pasteboard.changeCount
        guard let item = pasteboard.read() else { return .nothingToSend }
        return await offer(item)
    }

    private func offer(_ item: ClipboardItem) async -> SendOutcome {
        offered[item.kind] = item
        lastOfferedHash = item.hash
        do {
            try await transport.sendClip(.clipOffer(ClipOffer(kind: item.kind, size: item.size, hash: item.hash)))
            log.notice("clipboard offered kind=\(item.kind.rawValue, privacy: .public) size=\(item.data.count, privacy: .public)")
            return .sent(item.kind)
        } catch {
            log.error("clip.offer failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    // MARK: Nhận

    public func handle(_ message: ControlMessage) async {
        switch message {
        case .clipOffer, .clipPull, .clipData: break
        default: return
        }
        guard await isEnabled() else {
            log.notice("clipboard message ignored: permission off")
            return
        }
        switch message {
        case .clipOffer(let offer): await pullIfWanted(offer)
        case .clipPull(let pull): await send(kind: pull.kind)
        case .clipData(let header): receiver.begin(header)
        default: break
        }
    }

    /// Frame bulk (thuộc `clip.data` gần nhất).
    public func handleBulk(_ chunk: [UInt8]) async {
        guard receiver.isReceiving else { return }
        guard await isEnabled() else { receiver.reset(); return }
        do {
            if let item = try receiver.append(chunk) { apply(item) }
        } catch {
            receiver.reset()
            log.error("clipboard transfer dropped: \(String(describing: error), privacy: .public)")
        }
    }

    private func pullIfWanted(_ offer: ClipOffer) async {
        if let hash = offer.hash, isRecentRemote(hash) { return }
        do { try await transport.sendClip(.clipPull(ClipPull(kind: offer.kind))) } catch {
            log.error("clip.pull failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func send(kind: ClipKind) async {
        guard let item = offered[kind] else { return }
        do {
            try await transport.sendClipData(ClipData(kind: kind, size: item.size, hash: item.hash), payload: item.data)
        } catch {
            log.error("clip.data failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func isRecentRemote(_ hash: String) -> Bool {
        guard let recentRemote, recentRemote.hash == hash else { return false }
        return ContinuousClock.now - recentRemote.at < echoWindow
    }

    private func apply(_ item: ClipboardItem) {
        let count = pasteboard.write(item)
        seenChangeCount = count
        recentRemote = (item.hash, .now)
        lastOfferedHash = nil
        log.notice("clipboard received kind=\(item.kind.rawValue, privacy: .public) size=\(item.data.count, privacy: .public)")
    }
}
