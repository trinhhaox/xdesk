import CryptoKit
import Foundation

/// Danh tính thiết bị: khoá tĩnh X25519 + dấu vân tay hiển thị cho người dùng.
public struct DeviceIdentity: Sendable, Redacted {
    public let privateKey: Curve25519.KeyAgreement.PrivateKey

    public init(privateKey: Curve25519.KeyAgreement.PrivateKey) { self.privateKey = privateKey }

    public var publicKey: [UInt8] { Array(privateKey.publicKey.rawRepresentation) }
    public var fingerprint: String { DeviceFingerprint.make(publicKey: publicKey) }
}

public enum DeviceFingerprint {
    /// 8 byte đầu của SHA-256(pub), hex hoa chia nhóm 4: `AB12-CD34-EF56-7890`. Cũng là `id` thiết bị đã ghép.
    public static func make(publicKey: [UInt8]) -> String {
        let hex = SHA256.hash(data: publicKey).prefix(8).map { String(format: "%02X", $0) }.joined()
        return stride(from: 0, to: hex.count, by: 4).map { start in
            let from = hex.index(hex.startIndex, offsetBy: start)
            return String(hex[from..<hex.index(from, offsetBy: 4)])
        }.joined(separator: "-")
    }
}

public enum IdentityStoreError: Error, Equatable, Sendable {
    case keychain(Int32)
    /// Data-protection keychain bị từ chối (`errSecMissingEntitlement`): app cần ký với Team ID/entitlement `application-identifier`.
    case dataProtectionKeychainUnavailable
    case corrupt
    case unsupportedSchema(Int)
}

public protocol DeviceIdentityStoring: Sendable {
    /// Trả khoá đã lưu, hoặc tạo khoá mới và lưu lần đầu.
    func loadOrCreate() throws -> DeviceIdentity
    /// Xoá khoá (đặt lại danh tính); lần `loadOrCreate` sau tạo khoá mới.
    func delete() throws
}
