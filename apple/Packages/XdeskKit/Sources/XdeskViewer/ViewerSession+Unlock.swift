import Foundation
import XdeskCrypto
import XdeskTransport
import XdeskWire

extension ViewerSession {
    /// Đăng ký khoá công khai của điện thoại với host (TOFU) khi phiên bắt đầu và mỗi lần bấm mở khoá, nếu host hỗ trợ chứng thực.
    func registerUnlockKey(on connection: ControlConnection, negotiated: Capabilities) async {
        guard negotiated.contains(.unlockAttestation), let unlockSigner else { return }
        do {
            let pub = try await unlockSigner.publicKey()
            _ = try await connection.send(.unlockKey(UnlockKey(pub: Data(pub).base64EncodedString())))
        } catch {
            log.error("unlock.key failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Người dùng bấm "Mở khoá Mac": mở cờ chờ thử thách (30 s), gửi lại khoá công khai rồi xin thử thách.
    func requestUnlock() async {
        guard let connection else { return }
        unlockGate.arm()
        await registerUnlockKey(on: connection, negotiated: negotiatedCaps)
        _ = try? await connection.send(.systemUnlock(SystemUnlock()))
    }

    /// Host gửi thử thách: ký `"xdesk v1 unlock" || hostKey || viewerKey || nonce` (hiện Face ID / vân tay) rồi trả lời `system.unlock{sig}`.
    /// Thử thách không do người dùng vừa yêu cầu bị bỏ.
    func answerUnlockChallenge(_ challenge: SystemUnlockChallenge) async {
        guard unlockGate.consume() else {
            log.notice("bỏ system.unlock.challenge không được yêu cầu")
            return
        }
        guard let connection, let unlockSigner, let nonce = UnlockAttestation.decodeNonce(challenge.nonce),
              let hostKey = connectedHostKey, let viewerKey = trust?.identity.publicKey
        else { return }
        let message = UnlockKeyFormat.signedMessage(hostKey: hostKey, viewerKey: viewerKey, nonce: nonce)
        do {
            let signature = try await unlockSigner.sign(message: message, hostName: connectedHostName ?? "Mac")
            _ = try await connection.send(.systemUnlock(SystemUnlock(sig: Data(signature).base64EncodedString())))
        } catch UnlockSigningError.cancelled {
            lastUnlockResult = SystemUnlockResult(ok: false, message: String(localized: "Đã huỷ xác thực mở khoá Mac", bundle: .module))
        } catch {
            log.error("unlock sign failed: \(error.localizedDescription, privacy: .public)")
            lastUnlockResult = SystemUnlockResult(ok: false, message: String(localized: "Không xác thực được để mở khoá Mac", bundle: .module))
        }
    }
}
