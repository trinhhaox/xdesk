import CoreGraphics
import Foundation
import os

/// Khoá màn hình Mac thật, không chỉ tắt màn hình: `pmset displaysleepnow` chỉ khoá khi người dùng đã bật
/// "Yêu cầu mật khẩu sau khi ngủ", nên chỉ dùng làm phương án cuối.
/// Thứ tự: hàm khoá của hệ thống (login.framework, chính là thứ menu Apple › Khoá màn hình gọi) → phím ⌃⌘Q
/// có gửi cả phím bổ trợ (CGEvent chỉ gắn cờ ⌃⌘ không được WindowServer nhận là phím tắt hệ thống) → tắt màn hình.
enum RemoteLockExecutor {
    enum Outcome: Equatable { case locked, displaySleptOnly }

    private static let log = Logger(subsystem: "vn.xox.xdesk", category: "remote-lock")
    /// Mã phím ANSI: Q, Control trái, Command trái.
    static let qKeyCode: CGKeyCode = 12
    static let controlKeyCode: CGKeyCode = 59
    static let commandKeyCode: CGKeyCode = 55

    static func lockScreen(
        isLocked: () -> Bool = { LockScreenState.current().locked },
        attempts: [() -> Bool] = [lockViaLoginFramework, postControlCommandQ],
        sleepDisplay: () -> Void = displaySleepNow,
        sleep: (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) async -> Outcome {
        if isLocked() { return .locked }
        for (index, attempt) in attempts.enumerated() {
            guard attempt() else { continue }
            for _ in 0..<10 {
                await sleep(.milliseconds(150))
                if isLocked() { return .locked }
            }
            log.error("Cách khoá thứ \(index + 1) không khoá được màn hình")
        }
        log.error("Không khoá được màn hình, chuyển sang tắt màn hình")
        sleepDisplay()
        return .displaySleptOnly
    }

    /// Phản hồi cho viewer: chỉ tắt màn hình (không khoá) là thất bại vì Mac vẫn mở khi đánh thức lại.
    static func result(for outcome: Outcome) -> (ok: Bool, message: String) {
        switch outcome {
        case .locked: (true, "Đã khoá Mac")
        case .displaySleptOnly: (false, "Mac chỉ tắt màn hình — bật 'Yêu cầu mật khẩu' trong Cài đặt Mac")
        }
    }

    /// `SACLockScreenImmediate` trong login.framework (riêng tư): nạp động, không có thì trả false để thử cách khác.
    static func lockViaLoginFramework() -> Bool {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else { return false }
        typealias LockFunction = @convention(c) () -> Int32
        let status = unsafeBitCast(symbol, to: LockFunction.self)()
        if status != 0 { log.error("SACLockScreenImmediate trả mã \(status)") }
        return true
    }

    /// Nhấn ⌃ ⌘ Q như người dùng thật: xuống phím bổ trợ → Q → nhả theo thứ tự ngược.
    static func postControlCommandQ() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        let steps: [(CGKeyCode, Bool, CGEventFlags)] = [
            (controlKeyCode, true, [.maskControl]),
            (commandKeyCode, true, [.maskControl, .maskCommand]),
            (qKeyCode, true, [.maskControl, .maskCommand]),
            (qKeyCode, false, [.maskControl, .maskCommand]),
            (commandKeyCode, false, [.maskControl]),
            (controlKeyCode, false, []),
        ]
        for (key, down, flags) in steps {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return false }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        return true
    }

    private static func displaySleepNow() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
    }
}
