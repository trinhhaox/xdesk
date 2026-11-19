import Foundation
import os

/// Cách tắt/bật tiếng loa Mac (CoreAudio thật, hoặc giả lập khi test).
protocol OutputMuteBackend: Sendable {
    /// UID của thiết bị ra mặc định.
    func defaultOutputUID() -> String?
    /// `nil` = thiết bị không hỗ trợ tắt tiếng.
    func isMuted(uid: String) -> Bool?
    @discardableResult func setMuted(_ muted: Bool, uid: String) -> Bool
}

/// "Chỉ phát trên thiết bị": tắt tiếng loa Mac khi đang stream audio, và LUÔN trả lại như cũ.
///
/// An toàn:
/// 1. Chỉ tắt tiếng khi loa đang BẬT tiếng; nếu người dùng đã tắt sẵn thì không đụng gì (không có gì để khôi phục).
/// 2. Ghi `audio-mute-restore.json` (UID thiết bị) TRƯỚC khi tắt; xoá file sau khi bật lại. Nếu app chết giữa chừng
///    (crash, kill -9, mất điện) thì lần mở app kế tiếp `recoverAfterCrash()` thấy file và bật tiếng lại ngay.
/// 3. Đếm số phiên đang dùng: tắt ở phiên đầu, bật lại khi phiên cuối kết thúc (hoặc khi app thoát bình thường).
/// 4. Khôi phục dùng đúng UID đã tắt, không theo "thiết bị mặc định hiện tại" (người dùng có thể đã đổi tai nghe).
/// SCK ghi âm trước bước tắt tiếng của thiết bị nên viewer vẫn nghe đủ (xem docs/audio-and-usb.md).
final class OutputMuteGuard: @unchecked Sendable {
    struct Record: Codable, Equatable { let deviceUID: String }

    private struct State {
        var users = 0
        var mutedUID: String?
    }

    private let backend: any OutputMuteBackend
    private let stateURL: URL
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let log = Logger(subsystem: "vn.xox.xdesk", category: "output-mute")

    init(backend: any OutputMuteBackend, stateURL: URL) {
        self.backend = backend
        self.stateURL = stateURL
    }

    /// Gọi lúc khởi động app: nếu lần trước chết khi đang tắt tiếng → bật lại.
    @discardableResult
    func recoverAfterCrash() -> Bool {
        guard let data = try? Data(contentsOf: stateURL) else { return false }
        defer { removeRecord() }
        guard let record = try? JSONDecoder().decode(Record.self, from: data) else {
            log.error("audio-mute-restore.json hỏng, bỏ qua")
            return false
        }
        let restored = backend.isMuted(uid: record.deviceUID) == true && backend.setMuted(false, uid: record.deviceUID)
        log.notice("khôi phục tiếng loa sau lần chạy trước: \(restored, privacy: .public)")
        return restored
    }

    /// Một phiên audio bắt đầu. Trả `true` nếu loa đang bị tắt bởi Xdesk (kể cả bởi phiên khác).
    @discardableResult
    func engage() -> Bool {
        state.withLock { s in
            s.users += 1
            if s.mutedUID != nil { return true }
            guard let uid = backend.defaultOutputUID(), backend.isMuted(uid: uid) == false else { return false }
            guard writeRecord(Record(deviceUID: uid)) else { return false }
            guard backend.setMuted(true, uid: uid) else {
                removeRecord()
                return false
            }
            s.mutedUID = uid
            return true
        }
    }

    /// Một phiên kết thúc; phiên cuối bật lại tiếng.
    func release() {
        state.withLock { s in
            s.users = max(0, s.users - 1)
            guard s.users == 0 else { return }
            restoreLocked(&s)
        }
    }

    /// App thoát: bật lại bất kể còn phiên nào.
    func restoreNow() {
        state.withLock { s in
            s.users = 0
            restoreLocked(&s)
        }
    }

    var isMutingOutput: Bool { state.withLock { $0.mutedUID != nil } }

    private func restoreLocked(_ s: inout State) {
        guard let uid = s.mutedUID else { return }
        s.mutedUID = nil
        if !backend.setMuted(false, uid: uid) { log.error("không bật lại được tiếng loa \(uid, privacy: .private)") }
        removeRecord()
    }

    private func writeRecord(_ record: Record) -> Bool {
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: stateURL, options: .atomic)
            return true
        } catch {
            log.error("không ghi được file khôi phục, không tắt tiếng: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func removeRecord() {
        try? FileManager.default.removeItem(at: stateURL)
    }
}
