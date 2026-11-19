import Foundation
import os
import Security
import XdeskAgent

enum McpTokenStoreError: Error, CustomStringConvertible {
    case keychain(OSStatus)
    case corrupt

    var description: String {
        switch self {
        case .keychain(let status): "Keychain lỗi \(status)"
        case .corrupt: "Token trong Keychain bị hỏng"
        }
    }
}

/// Bearer token của MCP trong Keychain (generic password, chỉ trên máy này). Bản nhớ trong RAM để kiểm mỗi request không chạm Keychain.
final class McpTokenStore: Sendable {
    private static let service = "vn.xox.xdesk.mcp"
    private static let account = "bearer-token"

    private let cache = OSAllocatedUnfairLock<String?>(initialState: nil)

    /// Token đang hiệu lực (nil nếu chưa nạp); `RequestGuard` đọc hàm này mỗi request nên đổi token có hiệu lực ngay.
    var cachedToken: String? { cache.withLock { $0 } }

    func loadOrCreate() throws -> String {
        if let token = try read() {
            cache.withLock { $0 = token }
            return token
        }
        return try rotate()
    }

    func rotate() throws -> String {
        let token = try McpToken.generate()
        try delete()
        try add(token)
        cache.withLock { $0 = token }
        return token
    }

    private func query(dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: Self.account]
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        return query
    }

    /// Ưu tiên data-protection keychain; bản ký ad-hoc thiếu entitlement thì dùng login keychain.
    private func read() throws -> String? {
        for dataProtection in [true, false] {
            var request = query(dataProtection: dataProtection)
            request[kSecReturnData as String] = true
            request[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            switch SecItemCopyMatching(request as CFDictionary, &result) {
            case errSecSuccess:
                guard let data = result as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else { throw McpTokenStoreError.corrupt }
                return token
            case errSecItemNotFound, errSecMissingEntitlement: continue
            case let status: throw McpTokenStoreError.keychain(status)
            }
        }
        return nil
    }

    private func delete() throws {
        for dataProtection in [true, false] {
            switch SecItemDelete(query(dataProtection: dataProtection) as CFDictionary) {
            case errSecSuccess, errSecItemNotFound, errSecMissingEntitlement: continue
            case let status: throw McpTokenStoreError.keychain(status)
            }
        }
    }

    private func add(_ token: String) throws {
        for dataProtection in [true, false] {
            var attributes = query(dataProtection: dataProtection)
            attributes[kSecValueData as String] = Data(token.utf8)
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            attributes[kSecAttrSynchronizable as String] = false
            switch SecItemAdd(attributes as CFDictionary, nil) {
            case errSecSuccess: return
            case errSecMissingEntitlement where dataProtection: continue
            case let status: throw McpTokenStoreError.keychain(status)
            }
        }
    }
}
