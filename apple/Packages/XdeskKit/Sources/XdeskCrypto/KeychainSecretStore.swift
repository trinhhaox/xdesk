import Foundation
import os
import Security

public enum KeychainBackend: Sendable, Equatable {
    /// Data-protection keychain (`kSecUseDataProtectionKeychain`): `kSecAttrAccessible…ThisDeviceOnly` được thi hành thật.
    case dataProtection
    /// Login keychain kiểu file cũ trên macOS: cờ accessibility bị bỏ qua, item có thể bị migrate/backup, truy cập qua ACL/prompt.
    case legacyFileKeychain
}

public enum DataProtectionPolicy: Sendable {
    /// Không có data-protection keychain (thiếu entitlement/Team ID, ví dụ binary ký ad-hoc hay `swift test`) → ném `dataProtectionKeychainUnavailable`.
    case required
    /// Thử data-protection trước; bị từ chối `errSecMissingEntitlement` thì dùng login keychain cũ (xem `backend`).
    case preferred
}

/// Một bí mật nhỏ trong Keychain (generic password), `…AfterFirstUnlockThisDeviceOnly`, không đồng bộ iCloud.
/// Dùng chung cho khoá tĩnh X25519 và khoá MAC của danh sách thiết bị.
public final class KeychainSecretStore: Sendable {
    private let service: String
    private let account: String
    private let policy: DataProtectionPolicy
    private let usedBackend = OSAllocatedUnfairLock<KeychainBackend?>(initialState: nil)

    init(service: String, account: String, policy: DataProtectionPolicy) {
        self.service = service
        self.account = account
        self.policy = policy
    }

    /// Keychain thực sự chứa item ở lần thao tác thành công gần nhất (nil nếu chưa có thao tác nào).
    /// App đã ký phải kiểm `== .dataProtection`; `.legacyFileKeychain` nghĩa là cấu hình ký/entitlement chưa đúng.
    public var backend: KeychainBackend? { usedBackend.withLock { $0 } }

    private var candidates: [KeychainBackend] {
        policy == .required ? [.dataProtection] : [.dataProtection, .legacyFileKeychain]
    }

    func loadOrCreate(generate: () -> Data) throws -> Data {
        if let existing = try read() { return existing }
        let created = generate()
        switch try add(created) {
        case .added: return created
        case .duplicate:
            guard let raced = try read() else { throw IdentityStoreError.keychain(errSecDuplicateItem) }
            return raced
        }
    }

    func read() throws -> Data? {
        for backend in candidates {
            var query = baseQuery(backend)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            switch SecItemCopyMatching(query as CFDictionary, &result) {
            case errSecSuccess:
                guard let data = result as? Data else { throw IdentityStoreError.corrupt }
                record(backend)
                return data
            case errSecItemNotFound: continue
            case errSecMissingEntitlement: try rejectMissingEntitlement()
            case let status: throw IdentityStoreError.keychain(status)
            }
        }
        return nil
    }

    func delete() throws {
        for backend in candidates {
            switch SecItemDelete(baseQuery(backend) as CFDictionary) {
            case errSecSuccess, errSecItemNotFound: continue
            case errSecMissingEntitlement: try rejectMissingEntitlement()
            case let status: throw IdentityStoreError.keychain(status)
            }
        }
    }

    private enum AddResult { case added, duplicate }

    private func add(_ data: Data) throws -> AddResult {
        for backend in candidates {
            var attributes = baseQuery(backend)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            attributes[kSecAttrSynchronizable as String] = false
            switch SecItemAdd(attributes as CFDictionary, nil) {
            case errSecSuccess:
                record(backend)
                return .added
            case errSecDuplicateItem: return .duplicate
            case errSecMissingEntitlement: try rejectMissingEntitlement()
            case let status: throw IdentityStoreError.keychain(status)
            }
        }
        throw IdentityStoreError.dataProtectionKeychainUnavailable
    }

    /// `.required` → lỗi rõ ràng; `.preferred` → để vòng lặp thử keychain cũ.
    private func rejectMissingEntitlement() throws {
        if policy == .required { throw IdentityStoreError.dataProtectionKeychainUnavailable }
    }

    private func record(_ backend: KeychainBackend) { usedBackend.withLock { $0 = backend } }

    private func baseQuery(_ backend: KeychainBackend) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
        ]
        if backend == .dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        return query
    }
}
