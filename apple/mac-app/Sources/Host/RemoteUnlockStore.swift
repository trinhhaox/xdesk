import AppKit
import CoreGraphics
import Foundation
import os
import Security

enum RemoteUnlockOutcome: Sendable, Equatable {
    case unlocked(String)
    case wokeOnly(String)
    case failed(String)

    var ok: Bool {
        switch self {
        case .unlocked, .wokeOnly: true
        case .failed: false
        }
    }

    var message: String {
        switch self {
        case .unlocked(let msg), .wokeOnly(let msg), .failed(let msg): msg
        }
    }
}

/// Fail-Closed: chỉ cho phép mở khoá thật khi công tắc tổng trên Mac BẬT VÀ thiết bị đó được cấp quyền `unlock`.
enum RemoteUnlockPolicy {
    static func canUnlock(globalEnabled: Bool, deviceAllowed: Bool) -> Bool {
        globalEnabled && deviceAllowed
    }
}

/// Giới hạn số lần thử mở khoá mỗi phiên: tối đa 3 lần trong 60 giây.
struct RemoteUnlockRateLimiter: Sendable {
    let maxAttempts: Int
    let windowSeconds: Double
    private var timestamps: [TimeInterval] = []

    init(maxAttempts: Int = 3, windowSeconds: Double = 60) {
        self.maxAttempts = maxAttempts
        self.windowSeconds = windowSeconds
    }

    mutating func allowAttempt(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        timestamps.removeAll { now - $0 >= windowSeconds }
        guard timestamps.count < maxAttempts else { return false }
        timestamps.append(now)
        return true
    }
}

/// Lưu mật khẩu đăng nhập macOS cục bộ trong Keychain (không đồng bộ iCloud, giải phóng khỏi RAM ngay sau khi gõ).
struct RemoteUnlockKeychain: Sendable {
    static let shared = RemoteUnlockKeychain()

    let service: String
    let account: String

    init(service: String = "vn.xox.xdesk.remote-unlock", account: String = "macos-login-password") {
        self.service = service
        self.account = account
    }

    func hasPassword() -> Bool {
        (try? withPasswordBytes { !$0.isEmpty }) ?? false
    }

    func save(password: String) throws {
        var bytes = Array(password.utf8)
        defer { wipe(&bytes) }
        guard !bytes.isEmpty else {
            try delete()
            return
        }
        let data = Data(bytes)
        try delete()
        var lastStatus: OSStatus = errSecMissingEntitlement
        for useDataProtection in [true, false] {
            var attrs: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                kSecAttrSynchronizable as String: false,
            ]
            if useDataProtection { attrs[kSecUseDataProtectionKeychain as String] = true }
            let status = SecItemAdd(attrs as CFDictionary, nil)
            if status == errSecSuccess { return }
            lastStatus = status
            if status != errSecMissingEntitlement { break }
        }
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(lastStatus), userInfo: [
            NSLocalizedDescriptionKey: "Không lưu được vào Keychain (mã \(lastStatus))",
        ])
    }

    func delete() throws {
        for useDataProtection in [true, false] {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            if useDataProtection { query[kSecUseDataProtectionKeychain as String] = true }
            let status = SecItemDelete(query as CFDictionary)
            if status == errSecSuccess || status == errSecItemNotFound || status == errSecMissingEntitlement { continue }
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Không xoá được mật khẩu trong Keychain (mã \(status))",
            ])
        }
    }

    func withPasswordBytes<T>(_ body: ([UInt8]) throws -> T) throws -> T? {
        for useDataProtection in [true, false] {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            if useDataProtection { query[kSecUseDataProtectionKeychain as String] = true }
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecSuccess, let data = result as? Data {
                var bytes = [UInt8](data)
                defer { wipe(&bytes) }
                return try body(bytes)
            }
            if status == errSecItemNotFound || status == errSecMissingEntitlement { continue }
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Không đọc được mật khẩu từ Keychain (mã \(status))",
            ])
        }
        return nil
    }

    private func wipe(_ buffer: inout [UInt8]) {
        for i in buffer.indices { buffer[i] = 0 }
        buffer.removeAll(keepingCapacity: false)
    }
}

enum RemoteUnlockExecutor {
    private static let log = Logger(subsystem: "vn.xox.xdesk", category: "remote-unlock")

    static func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) == true
    }

    static func wakeDisplay() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-u", "-t", "5"]
        try? process.run()
    }

    static func performUnlock(keychain: RemoteUnlockKeychain = .shared) async -> RemoteUnlockOutcome {
        wakeDisplay()
        try? await Task.sleep(for: .milliseconds(350))
        guard isScreenLocked() else {
            return .wokeOnly("Đã đánh thức màn hình Mac")
        }
        guard AccessibilityPermission.isGranted else {
            return .failed("Mac chưa cấp quyền Trợ năng để nhập mật khẩu mở khoá")
        }
        do {
            let typed = try keychain.withPasswordBytes { bytes -> Bool in
                guard !bytes.isEmpty else { return false }
                let str = String(decoding: bytes, as: UTF8.self)
                var utf16 = Array(str.utf16)
                defer {
                    for i in utf16.indices { utf16[i] = 0 }
                    utf16.removeAll(keepingCapacity: false)
                }
                typeUnicodeBuffer(utf16)
                return true
            } ?? false
            guard typed else {
                return .failed("Chưa lưu mật khẩu mở khoá trong Cài đặt Mac")
            }
            try? await Task.sleep(for: .milliseconds(60))
            pressReturnKey()
            log.notice("Đã gửi mật khẩu mở khoá màn hình Mac từ xa")
            return .unlocked("Đã gửi lệnh mở khoá Mac")
        } catch {
            log.error("Mở khoá từ xa lỗi: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    private static func typeUnicodeBuffer(_ utf16: [UInt16]) {
        let source = CGEventSource(stateID: .hidSystemState)
        var offset = 0
        let chunkLimit = 20
        while offset < utf16.count {
            let end = min(offset + chunkLimit, utf16.count)
            var chunk = Array(utf16[offset..<end])
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                event.post(tap: .cghidEventTap)
            }
            for i in chunk.indices { chunk[i] = 0 }
            offset = end
        }
    }

    private static func pressReturnKey() {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: down)?.post(tap: .cghidEventTap)
        }
    }
}
