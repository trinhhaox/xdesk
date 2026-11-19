import Foundation
import XdeskCrypto
import XdeskWire

/// Cách viewer xác thực với host.
public enum ViewerAuthMode: Sendable {
    /// IK: biết khoá host đã ghép.
    case reconnect(hostKey: [UInt8])
    /// XXpsk3: quét QR; khoá host trong QR được ghim trước khi gửi message 3.
    case qr(PairingURI)
    /// XX + SAS: so mã 6 số. `onCode` nhận "NNN NNN" để hiện lên màn hình trong lúc chờ host bấm "Khớp".
    case sas(onCode: @Sendable (String) async -> Void)
}

public struct InitiatorOutcome: Sendable, Equatable {
    public let hostKey: [UInt8]
    public let hostName: String
    public let method: AuthenticatedPeer.Method
}

extension ControlConnection {
    /// Thời gian tối đa chờ host duyệt ghép đôi (người dùng thao tác).
    public static let pairingDecisionTimeoutSeconds = 120.0

    /// Bắt tay Noise phía viewer (initiator). Xong thì kênh đã mã hoá; tiếp tục `performViewerHandshake` (hello/welcome).
    public func performInitiatorHandshake(
        identity: DeviceIdentity, deviceName: String, mode: ViewerAuthMode
    ) async throws -> InitiatorOutcome {
        let outcome: InitiatorOutcome
        do {
            outcome = try await withDeadline(seconds: Self.handshakeTotalTimeoutSeconds) {
                try await runInitiator(identity: identity, deviceName: deviceName, mode: mode)
            }
        } catch {
            close()
            throw error
        }
        if case .reconnect = mode { return outcome }
        try await awaitPairingResult()
        return outcome
    }

    private func runInitiator(identity: DeviceIdentity, deviceName: String, mode: ViewerAuthMode) async throws -> InitiatorOutcome {
        let pattern: NoisePattern
        var hostKeyHint: [UInt8]?
        var psk: [UInt8]?
        switch mode {
        case .reconnect(let key): (pattern, hostKeyHint) = (.ik, key)
        case .qr(let uri): (pattern, psk) = (.xxPsk3, uri.token)
        case .sas: pattern = .xx
        }
        let state = try NoiseSessionBox(
            pattern: pattern, role: .initiator, staticKey: identity.privateKey, remoteStaticKey: hostKeyHint, psk: psk)
        try await sendHandshake(.begin(pattern))

        let nonce = ShortAuthString.randomNonce()
        let hello = pattern == .ik ? try HandshakePayload(role: .viewer, deviceName: deviceName).encode() : []
        let message1 = try state.write(payload: hello)
        if pattern == .xx, let ephemeral = state.localEphemeralKey {
            try await sendHandshake(.commit(try ShortAuthString.commitment(ephemeralKey: ephemeral, staticKey: identity.publicKey, nonce: nonce)))
        }
        try await sendHandshake(.noise(message1))

        let hostPayload = try HandshakePayload.decode(try state.read(try await nextNoise(Self.handshakeMessageTimeoutSeconds)))
        guard hostPayload.role == .host, let hostKey = hostKeyHint ?? state.remoteStaticKey else { throw CryptoError.invalidHandshakePayload }
        if case .qr(let uri) = mode, !ConstantTime.equals(hostKey, uri.hostPublicKey) { throw TransportError.hostKeyMismatch }

        var method = AuthenticatedPeer.Method.reconnect
        if pattern != .ik {
            let payload = HandshakePayload(role: .viewer, deviceName: deviceName, sasNonce: pattern == .xx ? nonce : nil)
            try await sendHandshake(.noise(try state.write(payload: try payload.encode())))
            method = pattern == .xx ? .sasPaired : .qrPaired
        }
        if case .sas(let onCode) = mode, let h2 = state.messageTwoHash {
            let code = ShortAuthString.format(try ShortAuthString.code(messageTwoHash: h2, nonce: nonce))
            installSession(keys: try state.sessionKeys())
            Task { await onCode(code) }
        } else {
            installSession(keys: try state.sessionKeys())
        }
        return InitiatorOutcome(hostKey: hostKey, hostName: hostPayload.deviceName, method: method)
    }

    /// XX/XXpsk3: host phản hồi `pair.result` sau khi người dùng quyết định.
    private func awaitPairingResult() async throws {
        let accepted: Bool = try await withDeadline(seconds: Self.pairingDecisionTimeoutSeconds) {
            guard let inbound = try await nextInbound() else { throw TransportError.connectionClosed }
            guard case .message(let envelope) = inbound else { throw TransportError.protocolViolation("cần pair.result") }
            if case .reject(let r) = envelope.message { throw TransportError.rejected(reason: r.reason, detail: r.detail) }
            guard case .pairResult(let result) = envelope.message else { throw TransportError.protocolViolation("cần pair.result") }
            return result.accepted
        }
        guard accepted else { throw TransportError.pairingDenied }
    }
}
