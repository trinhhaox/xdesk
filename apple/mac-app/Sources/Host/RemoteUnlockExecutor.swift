import CoreGraphics
import Foundation
import os

/// Trạng thái màn hình khoá đọc từ hệ thống (tách ra để test được logic chờ/huỷ).
struct LockScreenState: Sendable, Equatable {
    var locked: Bool
    var displayAwake: Bool

    static func current() -> LockScreenState {
        make(session: CGSessionCopyCurrentDictionary() as? [String: Any], displayAwake: CGDisplayIsAsleep(CGMainDisplayID()) == 0)
    }

    /// Chỉ coi là "đã khoá" khi phiên này đang ở console (`kCGSessionOnConsoleKey`): khi chuyển người dùng nhanh, phiên của ta
    /// khoá nhưng màn hình đang hiện phiên khác, gõ mật khẩu lúc đó sẽ rơi vào người dùng kia.
    static func make(session: [String: Any]?, displayAwake: Bool) -> LockScreenState {
        let locked = (session?["CGSSessionScreenIsLocked"] as? Bool) == true
        let onConsole = (session?[kCGSessionOnConsoleKey] as? Bool) == true
        return LockScreenState(locked: locked && onConsole, displayAwake: displayAwake)
    }
}

/// Chờ màn hình khoá sẵn sàng nhận mật khẩu thay vì đoán bằng một khoảng chờ cố định.
enum LockScreenWait {
    enum Result: Equatable { case ready, notLocked, timedOut }

    /// `ready` khi đã khoá + màn hình sáng trong `stableSamples` lần đo liên tiếp (giao diện khoá kịp hiện ô mật khẩu);
    /// `notLocked` khi màn hình sáng mà không khoá; hết giờ mà vẫn chưa sẵn sàng thì `timedOut`.
    static func wait(
        probe: () -> LockScreenState,
        interval: Duration = .milliseconds(150),
        timeout: Duration = .seconds(3),
        stableSamples: Int = 3,
        sleep: (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) async -> Result {
        var elapsed: Duration = .zero
        var stable = 0
        while true {
            let state = probe()
            if state.displayAwake && !state.locked { return .notLocked }
            stable = (state.locked && state.displayAwake) ? stable + 1 : 0
            if stable >= stableSamples { return .ready }
            if elapsed >= timeout { return state.locked ? .timedOut : .notLocked }
            await sleep(interval)
            elapsed += interval
        }
    }
}

/// Đổi mật khẩu UTF-8 sang UTF-16 để gõ mà không tạo `String` trung gian (String không xoá được khỏi bộ nhớ).
enum PasswordTranscoder {
    static func utf16(fromUTF8 bytes: [UInt8]) -> [UInt16]? {
        var out: [UInt16] = []
        out.reserveCapacity(bytes.count)
        let failed = transcode(bytes.makeIterator(), from: UTF8.self, to: UTF16.self, stoppingOnError: true) { out.append($0) }
        guard !failed else {
            for i in out.indices { out[i] = 0 }
            return nil
        }
        return out
    }
}

enum RemoteUnlockExecutor {
    private static let log = Logger(subsystem: "vn.xox.xdesk", category: "remote-unlock")
    /// Mỗi lần gõ tối đa 20 ký tự UTF-16 (giới hạn của `keyboardSetUnicodeString`).
    static let chunkLimit = 20

    static func isScreenLocked() -> Bool { LockScreenState.current().locked }

    static func wakeDisplay() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-u", "-t", "5"]
        try? process.run()
    }

    static func performUnlock(keychain: RemoteUnlockKeychain = .shared) async -> RemoteUnlockOutcome {
        wakeDisplay()
        switch await LockScreenWait.wait(probe: LockScreenState.current) {
        case .notLocked: return .wokeOnly(String(localized: "Đã đánh thức màn hình Mac"))
        case .timedOut: return .failed(String(localized: "Màn hình khoá chưa sẵn sàng, hãy thử lại"))
        case .ready: break
        }
        guard AccessibilityPermission.isGranted else {
            return .failed(String(localized: "Mac chưa cấp quyền Trợ năng để nhập mật khẩu mở khoá"))
        }
        do {
            let outcome = try keychain.withPasswordBytes { bytes -> RemoteUnlockOutcome in
                guard !bytes.isEmpty, var utf16 = PasswordTranscoder.utf16(fromUTF8: bytes) else {
                    return .failed(String(localized: "Chưa lưu mật khẩu mở khoá trong Cài đặt Mac"))
                }
                defer {
                    for i in utf16.indices { utf16[i] = 0 }
                    utf16.removeAll(keepingCapacity: false)
                }
                return typeWhileLocked(utf16, isLocked: { LockScreenState.current().locked })
            } ?? .failed(String(localized: "Chưa lưu mật khẩu mở khoá trong Cài đặt Mac"))
            if case .unlocked = outcome { log.notice("Đã gửi mật khẩu mở khoá màn hình Mac từ xa") }
            return outcome
        } catch {
            log.error("Mở khoá từ xa lỗi: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    /// Gõ từng đoạn, kiểm tra lại trạng thái khoá trước mỗi đoạn và trước Return: Mac vừa mở khoá
    /// (hoặc khoá đổi) thì dừng ngay để mật khẩu không rơi vào cửa sổ đang mở.
    static func typeWhileLocked(
        _ utf16: [UInt16],
        isLocked: () -> Bool,
        post: ([UInt16]) -> Void = postUnicode,
        pressReturn: () -> Void = pressReturnKey
    ) -> RemoteUnlockOutcome {
        var offset = 0
        while offset < utf16.count {
            guard isLocked() else { return .failed(String(localized: "Trạng thái khoá đã đổi, đã dừng nhập mật khẩu")) }
            let end = min(offset + chunkLimit, utf16.count)
            post(Array(utf16[offset..<end]))
            offset = end
        }
        guard isLocked() else { return .failed(String(localized: "Trạng thái khoá đã đổi, đã dừng nhập mật khẩu")) }
        pressReturn()
        return .unlocked(String(localized: "Đã gửi lệnh mở khoá Mac"))
    }

    private static func postUnicode(_ chunk: [UInt16]) {
        let source = CGEventSource(stateID: .hidSystemState)
        var buffer = chunk
        defer { for i in buffer.indices { buffer[i] = 0 } }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
            event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
            event.post(tap: .cghidEventTap)
        }
    }

    private static func pressReturnKey() {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: down)?.post(tap: .cghidEventTap)
        }
    }
}
