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
