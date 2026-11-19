import Foundation
import XdeskCrypto
import XdeskWire

extension ControlConnection {
    public static let handshakeMessageTimeoutSeconds = 5.0
    public static let handshakeTotalTimeoutSeconds = 30.0

    /// Gửi một frame bắt tay (kind 0x01).
    func sendHandshake(_ frame: HandshakeFrame) async throws {
        try await sendFrame(ControlFrame(kind: .handshake, payload: frame.encode()))
    }

    /// Đọc đúng một frame bắt tay trong hạn `timeoutSeconds`; quá hạn đóng kết nối và báo `timedOut`.
    func receiveHandshake(timeoutSeconds: Double = ControlConnection.handshakeMessageTimeoutSeconds) async throws -> HandshakeFrame {
        try await withDeadline(seconds: timeoutSeconds) {
            guard let frame = try await nextRawFrame() else { throw TransportError.connectionClosed }
            guard frame.kind == .handshake else { throw TransportError.protocolViolation("cần frame bắt tay") }
            do { return try HandshakeFrame.decode(frame.payload) } catch { throw TransportError.protocolViolation("frame bắt tay sai") }
        }
    }

    /// Chuyển sang kênh mã hoá (sau message cuối của Noise).
    func installSession(keys: SessionKeys) {
        cipher = ControlCipher(keys: keys)
        mode = .secured
        decoder.extraBulkAllowance = StreamFormat.tagLength
        udpKeys = UdpKeys(send: keys.udpSend, receive: keys.udpReceive)
    }

    func setPeer(_ peer: AuthenticatedPeer) { self.peer = peer }

    /// IK: chạy `hook` sau frame mã hoá hợp lệ đầu tiên của đối tác (M6), không phải sau message 1 (có thể bị phát lại).
    func addFirstFrameHook(_ hook: @escaping @Sendable () async -> Void) { firstFrameHooks.append(hook) }

    func setRekeyInterval(_ interval: Duration) { rekeyInterval = interval }

    var isSecured: Bool { mode == .secured }

    /// Đồng hồ canh một bước: quá hạn → đóng kết nối (đánh thức lần đọc đang chờ) và báo `timedOut`.
    func withDeadline<T: Sendable>(seconds: Double, _ body: () async throws -> T) async throws -> T {
        watchdogFired = false
        let watchdog = Task { [weak self] in
            try await Task.sleep(for: .seconds(seconds))
            await self?.fireWatchdog()
        }
        defer { watchdog.cancel() }
        do {
            return try await body()
        } catch {
            if watchdogFired { throw TransportError.timedOut }
            close()
            throw error
        }
    }

    func fireWatchdog() {
        watchdogFired = true
        close()
    }
}
