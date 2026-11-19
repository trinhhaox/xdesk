import CryptoKit
import XdeskCrypto

/// Giữ `NoiseHandshakeState` (không copy được) trong một đối tượng để các hàm async không giữ giá trị `~Copyable` qua `await`:
/// trình biên dịch Release (Xcode) không liên kết được coroutine như vậy. Mỗi bắt tay dùng một hộp, một task duy nhất.
final class NoiseSessionBox {
    private var state: NoiseHandshakeState

    init(
        pattern: NoisePattern, role: NoiseRole, staticKey: Curve25519.KeyAgreement.PrivateKey,
        remoteStaticKey: [UInt8]? = nil, psk: [UInt8]? = nil
    ) throws {
        state = try NoiseHandshakeState(pattern: pattern, role: role, staticKey: staticKey, remoteStaticKey: remoteStaticKey, psk: psk)
    }

    func write(payload: [UInt8] = []) throws -> [UInt8] { try state.writeMessage(payload: payload) }
    func read(_ message: [UInt8]) throws -> [UInt8] { try state.readMessage(message) }
    func sessionKeys() throws -> SessionKeys { try state.sessionKeys() }

    var localEphemeralKey: [UInt8]? { state.localEphemeralKey }
    var remoteStaticKey: [UInt8]? { state.remoteStaticKey }
    var remoteEphemeralKey: [UInt8]? { state.remoteEphemeralKey }
    var messageTwoHash: [UInt8]? { state.messageTwoHash }
}
