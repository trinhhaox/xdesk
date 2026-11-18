import CryptoKit
import Foundation

/// Cung cấp khoá HMAC 32 byte cho file danh sách thiết bị. Khoá nằm ngoài file (Keychain) nên tiến trình cùng user
/// chỉ sửa được file chứ không ký lại được.
public protocol PairedDevicesMACKeyProviding: Sendable {
    func loadOrCreate() throws -> SymmetricKey
}

/// Khoá MAC trong Keychain, cùng lớp truy cập với khoá tĩnh (`AfterFirstUnlockThisDeviceOnly`).
public struct KeychainPairedDevicesMACKeyStore: PairedDevicesMACKeyProviding {
    public static let keyLength = 32
    private let secret: KeychainSecretStore

    public init(service: String = "vn.xox.xdesk.paired-devices-mac", policy: DataProtectionPolicy = .preferred) {
        secret = KeychainSecretStore(service: service, account: "paired-devices-hmac-sha256", policy: policy)
    }

    public var backend: KeychainBackend? { secret.backend }

    public func loadOrCreate() throws -> SymmetricKey {
        let data = try secret.loadOrCreate { Data(SymmetricKey(size: .bits256).bytes) }
        guard data.count == Self.keyLength else { throw IdentityStoreError.corrupt }
        return SymmetricKey(data: data)
    }

    public func delete() throws { try secret.delete() }
}

/// Khoá cố định trong bộ nhớ cho test; không bền vững.
public struct InMemoryPairedDevicesMACKey: PairedDevicesMACKeyProviding {
    private let key: SymmetricKey

    public init(key: SymmetricKey = SymmetricKey(size: .bits256)) { self.key = key }

    public func loadOrCreate() throws -> SymmetricKey { key }
}

enum PairedDevicesIntegrity {
    private static let label = Array("xdesk v1 paired-devices".utf8) + [0]

    /// HMAC-SHA256 trên `nhãn | JSON chuẩn (không có trường mac)`.
    static func mac(for canonicalJSON: Data, key: SymmetricKey) -> [UInt8] {
        Array(HMAC<SHA256>.authenticationCode(for: label + canonicalJSON, using: key))
    }

    /// So sánh hằng thời gian (CryptoKit).
    static func isValid(_ mac: [UInt8], for canonicalJSON: Data, key: SymmetricKey) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: label + canonicalJSON, using: key)
    }
}
