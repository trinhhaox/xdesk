import CryptoKit
import Foundation
import os

/// Lưu khoá tĩnh trong Keychain (data-protection, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, không iCloud, không vào backup).
public struct KeychainDeviceIdentityStore: DeviceIdentityStoring {
    private let secret: KeychainSecretStore

    public init(service: String = "vn.xox.xdesk.identity", policy: DataProtectionPolicy = .preferred) {
        secret = KeychainSecretStore(service: service, account: "device-static-key-x25519", policy: policy)
    }

    /// Keychain đang dùng (xem `KeychainSecretStore.backend`).
    public var backend: KeychainBackend? { secret.backend }

    public func loadOrCreate() throws -> DeviceIdentity {
        let data = try secret.loadOrCreate { Curve25519.KeyAgreement.PrivateKey().rawRepresentation }
        guard let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) else { throw IdentityStoreError.corrupt }
        return DeviceIdentity(privateKey: key)
    }

    public func delete() throws { try secret.delete() }
}

/// Kho trong bộ nhớ cho test và preview; không bền vững.
public final class InMemoryDeviceIdentityStore: DeviceIdentityStoring {
    private let stored = OSAllocatedUnfairLock<DeviceIdentity?>(initialState: nil)

    public init() {}

    public func loadOrCreate() throws -> DeviceIdentity {
        stored.withLock { identity in
            if let identity { return identity }
            let created = DeviceIdentity(privateKey: Curve25519.KeyAgreement.PrivateKey())
            identity = created
            return created
        }
    }

    public func delete() throws { stored.withLock { $0 = nil } }
}
