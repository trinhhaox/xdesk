import Foundation
import XdeskCrypto
import XdeskWire

extension HostSession {
    private static let keyMismatchMessage = "Khoá Face ID/vân tay của điện thoại đã đổi. Trên Mac, vào Cài đặt Xdesk > Thiết bị và bấm \"Đặt lại khoá\" rồi thử lại"

    private func reply(_ ok: Bool, _ message: String) async {
        _ = try? await connection.send(.systemUnlockResult(SystemUnlockResult(ok: ok, message: message)))
    }

    /// `system.unlock` không có `sig` = xin thử thách; có `sig` = trả lời thử thách bằng chữ ký sinh trắc học.
    func handleSystemUnlock(_ request: SystemUnlock) async {
        if let sig = request.sig {
            await handleSignedUnlock(sigBase64: sig)
        } else {
            await handleUnlockChallengeRequest()
        }
    }

    /// Chính sách chung (cài đặt Mac + quyền thiết bị). Trả `false` nếu đã tự trả lời viewer.
    private func passesUnlockPolicy() async -> Bool {
        let livePerms = await livePermissions()
        let globalUnlock = await remoteUnlockLookup()
        if RemoteUnlockPolicy.canUnlock(globalEnabled: globalUnlock, deviceAllowed: livePerms.unlock) { return true }
        if livePerms.input && !RemoteUnlockExecutor.isScreenLocked() {
            RemoteUnlockExecutor.wakeDisplay()
            await reply(true, "Đã đánh thức màn hình Mac (mở khoá bằng mật khẩu đang tắt)")
        } else {
            await reply(false, "Mac chưa bật mở khoá từ xa cho thiết bị này")
        }
        return false
    }

    /// Khoá đã đăng ký của viewer hiện tại + kiểm tra điều kiện chứng thực; trả khoá nếu đủ điều kiện, ngược lại đã trả lời viewer.
    private func attestedKeyOrReply() async -> [UInt8]? {
        let viewerKey = await connection.peer?.publicKey
        let stored = if let viewerKey { await unlockKeyLookup(viewerKey) } else { nil as [UInt8]? }
        let check = UnlockAttestationPrecheck.evaluate(attestationNegotiated: negotiatedCaps.contains(.unlockAttestation), storedKey: stored)
        guard check == .ok, let stored else {
            // Viewer cũ / chưa có khoá: tuyệt đối không gõ mật khẩu, chỉ đánh thức màn hình.
            if check == .viewerNeedsUpdate || check == .keyNotEnrolled { RemoteUnlockExecutor.wakeDisplay() }
            await reply(false, check.message ?? "")
            return nil
        }
        return stored
    }

    private func handleUnlockChallengeRequest() async {
        guard unlockLimits.allow(.challenge, deviceKey: await connection.peer?.publicKey) else {
            await reply(false, "Thử mở khoá quá nhiều lần, vui lòng đợi 1 phút")
            return
        }
        guard await passesUnlockPolicy(), await attestedKeyOrReply() != nil else { return }
        let nonce = unlockChallenges.issue()
        let challenge = SystemUnlockChallenge(nonce: Data(nonce).base64EncodedString())
        do { _ = try await connection.send(.systemUnlockChallenge(challenge)) } catch {
            log.error("gửi system.unlock.challenge lỗi: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleSignedUnlock(sigBase64: String) async {
        guard unlockLimits.allow(.signed, deviceKey: await connection.peer?.publicKey) else {
            unlockChallenges.discard()
            await reply(false, "Thử mở khoá quá nhiều lần, vui lòng đợi 1 phút")
            return
        }
        guard await passesUnlockPolicy(), let key = await attestedKeyOrReply() else {
            unlockChallenges.discard()
            return
        }
        guard let hostKey = await hostStaticKey(), let viewerKey = await connection.peer?.publicKey else {
            unlockChallenges.discard()
            await reply(false, "Mac chưa xác định được khoá thiết bị, hãy kết nối lại")
            return
        }
        guard let signature = Data(base64Encoded: sigBase64) else {
            unlockChallenges.discard()
            await reply(false, "Chữ ký mở khoá không hợp lệ")
            return
        }
        switch unlockChallenges.consume(publicKey: key, hostKey: hostKey, viewerKey: viewerKey, derSignature: Array(signature)) {
        case nil:
            let outcome = await RemoteUnlockExecutor.performUnlock()
            await reply(outcome.ok, outcome.message)
        case .noChallenge:
            await reply(false, "Yêu cầu mở khoá không hợp lệ hoặc đã dùng, hãy thử lại")
        case .expired:
            await reply(false, "Yêu cầu mở khoá đã hết hạn, hãy thử lại")
        case .badSignature:
            log.notice("Chữ ký mở khoá không khớp khoá đã đăng ký")
            await reply(false, "Xác thực sinh trắc học không hợp lệ. Nếu vừa đổi điện thoại/cài lại app, hãy đặt lại khoá trong Cài đặt Xdesk trên Mac")
        }
    }

    /// `unlock.key`: đăng ký khoá công khai (TOFU). Khoá khác khoá đã lưu không bao giờ ghi đè, chỉ báo cho người dùng Mac.
    func handleUnlockKey(_ message: UnlockKey) async {
        guard negotiatedCaps.contains(.unlockAttestation),
              let viewerKey = await connection.peer?.publicKey,
              let key = UnlockAttestation.decodePublicKey(message.pub),
              unlockLimits.allow(.key, deviceKey: viewerKey)
        else { return }
        switch await unlockKeyEnroll(viewerKey, key) {
        case .enrolled: log.notice("Đã đăng ký khoá mở khoá sinh trắc học của thiết bị")
        case .windowClosed: log.notice("Bỏ unlock.key: chưa có thao tác đăng ký khoá trên Mac trong 5 phút gần đây")
        case .mismatch:
            log.error("Thiết bị gửi khoá mở khoá khác khoá đã đăng ký, giữ khoá cũ")
            guard !unlockMismatchNotified else { return }
            unlockMismatchNotified = true
            onFileFailed(String(localized: "Mở khoá Mac"), String(localized: "Khoá Face ID/vân tay của một điện thoại đã đổi. Vào Cài đặt > Thiết bị và bấm \"Đặt lại khoá\" nếu bạn tin tưởng thiết bị."))
        case .alreadyEnrolled, .notPermitted, .invalidKey: break
        }
    }
}
