import Foundation
import LocalAuthentication
import Security
import XdeskViewer

/// Khoá ECDSA P-256 trong Secure Enclave, chỉ dùng được sau khi người dùng xác thực (`.userPresence`: Face ID/Touch ID hoặc mật mã máy,
/// quyết định sản phẩm: cho phép mật mã). Khoá không xuất ra khỏi chip và bị xoá khi đổi máy (ThisDeviceOnly).
/// Khoá chỉ được TẠO trong `publicKey()`; `sign` chỉ tra cứu. Cần thiết bị thật, không chạy được trên Simulator.
struct SecureEnclaveUnlockSigner: UnlockSigner {
    private static let tag = Data("vn.xox.xdesk.unlock-key".utf8)
    private static let flags: SecAccessControlCreateFlags = [.privateKeyUsage, .userPresence]

    func publicKey() async throws -> [UInt8] {
        try await Task.detached {
            let key = try Self.lookupKey(context: nil) ?? Self.createKey()
            return try Self.externalRepresentation(of: key)
        }.value
    }

    func existingPublicKey() async -> [UInt8]? {
        await Task.detached { (try? Self.lookupKey(context: nil)).flatMap { try? Self.externalRepresentation(of: $0) } }.value
    }

    func sign(message: [UInt8], hostName: String) async throws -> [UInt8] {
        try await Task.detached {
            // Không tạo khoá ở đây: thiếu khoá = chưa đăng ký, không hiện Face ID vô ích.
            guard try Self.lookupKey(context: nil) != nil else { throw UnlockSigningError.unavailable }
            let context = LAContext()
            guard let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, Self.flags, nil)
            else { throw UnlockSigningError.unavailable }
            do {
                // Hiện Face ID/mật mã với lời nhắc nêu tên Mac; context đã xác thực được dùng lại cho lần ký (không hỏi lần hai).
                _ = try await context.evaluateAccessControl(access, operation: .useKeySign, localizedReason: "Xác thực để mở khoá \(hostName)")
            } catch {
                throw Self.map(error)
            }
            guard let key = try Self.lookupKey(context: context) else { throw UnlockSigningError.unavailable }
            var signError: Unmanaged<CFError>?
            guard let der = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, Data(message) as CFData, &signError) as Data? else {
                throw Self.map(signError?.takeRetainedValue())
            }
            return Array(der)
        }.value
    }

    /// Tra khoá đã có; `nil` khi `errSecItemNotFound`, lỗi khác ném `.unavailable`.
    private static func lookupKey(context: LAContext?) throws -> SecKey? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]
        if let context { query[kSecUseAuthenticationContext as String] = context }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let item, CFGetTypeID(item) == SecKeyGetTypeID() else { throw UnlockSigningError.unavailable }
        return (item as! SecKey) // swiftlint:disable:this force_cast
    }

    private static func createKey() throws -> SecKey {
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, flags, nil) else {
            throw UnlockSigningError.unavailable
        }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessControl as String: access,
            ] as [String: Any],
        ]
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, nil) else { throw UnlockSigningError.unavailable }
        return key
    }

    private static func externalRepresentation(of key: SecKey) throws -> [UInt8] {
        guard let pub = SecKeyCopyPublicKey(key), let data = SecKeyCopyExternalRepresentation(pub, nil) as Data?,
              data.count == 65, data.first == 0x04
        else { throw UnlockSigningError.unavailable }
        return Array(data)
    }

    private static func map(_ error: any Error) -> UnlockSigningError {
        guard let la = error as? LAError else { return .unavailable }
        switch la.code {
        case .userCancel, .appCancel, .systemCancel: return .cancelled
        default: return .unavailable
        }
    }

    private static func map(_ error: CFError?) -> UnlockSigningError {
        guard let error else { return .unavailable }
        return CFErrorGetCode(error) == Int(errSecUserCanceled) ? .cancelled : .unavailable
    }
}
