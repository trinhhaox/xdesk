import Foundation
import XdeskCrypto
import XdeskWire

/// Kết quả phần Noise (trước chính sách): khoá phiên + dữ liệu cần cho cam kết/SAS.
private struct NoiseOutcome {
    let keys: SessionKeys
    let remoteStatic: [UInt8]
    let remoteEphemeral: [UInt8]
    let messageTwoHash: [UInt8]
    let payload: HandshakePayload
}

private struct HandshakeClock {
    private let start = ContinuousClock.now

    /// Hạn cho message kế tiếp: tối đa 5 s và không vượt tổng 30 s.
    func nextTimeout() throws -> Double {
        let elapsed = Double((ContinuousClock.now - start).components.seconds)
        let remaining = ControlConnection.handshakeTotalTimeoutSeconds - elapsed
        guard remaining > 0 else { throw TransportError.timedOut }
        return min(ControlConnection.handshakeMessageTimeoutSeconds, remaining)
    }
}

extension HostAuthenticator {
    /// Chạy bắt tay responder trên `connection`; trả đối tác đã xác thực hoặc ném lỗi (người gọi đóng kết nối).
    /// IK: khoá lạ → ném mà không gửi gì (không lộ thông tin). XXpsk3/XX: chỉ ghi thiết bị sau khi `decide` đồng ý.
    func accept(_ connection: ControlConnection) async throws -> AuthenticatedPeer {
        let clock = HandshakeClock()
        guard case .begin(let pattern) = try await connection.receiveHandshake(timeoutSeconds: clock.nextTimeout()) else {
            throw TransportError.protocolViolation("cần begin")
        }
        do {
            switch pattern {
            case .ik: return try await acceptReconnect(connection, clock)
            case .xxPsk3: return try await acceptQr(connection, clock)
            case .xx: return try await acceptSas(connection, clock)
            }
        } catch {
            if pattern == .xxPsk3 { qrFailed() }
            if pattern == .xx { limiter.recordFailure() }
            throw error
        }
    }

    // MARK: IK

    private func acceptReconnect(_ connection: ControlConnection, _ clock: HandshakeClock) async throws -> AuthenticatedPeer {
        let state = try NoiseSessionBox(pattern: .ik, role: .responder, staticKey: identity.privateKey)
        let viewerHello = try state.read(try await connection.nextNoise(clock.nextTimeout()))
        guard let remote = state.remoteStaticKey, let device = await store.device(publicKey: remote), device.role == .viewer else {
            throw TransportError.unknownDevice
        }
        let outcome = try await finish(state, connection: connection, clock: clock, viewerPayload: viewerHello)
        guard outcome.payload.role == .viewer else { throw CryptoError.invalidHandshakePayload }
        await connection.installSession(keys: outcome.keys)
        let peer = AuthenticatedPeer(
            publicKey: device.publicKey, name: device.name, role: .viewer, permissions: device.permissions, method: .reconnect)
        await connection.setPeer(peer)
        await connection.addFirstFrameHook { [self] in await authenticated(peer) }
        return peer
    }

    // MARK: XXpsk3 (QR)

    private func acceptQr(_ connection: ControlConnection, _ clock: HandshakeClock) async throws -> AuthenticatedPeer {
        guard let token = issuer.activeToken() else { throw TransportError.pairingClosed }
        let state = try NoiseSessionBox(pattern: .xxPsk3, role: .responder, staticKey: identity.privateKey, psk: token.bytes)
        _ = try state.read(try await connection.nextNoise(clock.nextTimeout()))
        let outcome = try await finish(state, connection: connection, clock: clock, viewerPayload: nil)
        guard outcome.payload.role == .viewer, outcome.payload.sasNonce == nil else { throw CryptoError.invalidHandshakePayload }
        guard issuer.consume(matching: token.bytes) else { throw TransportError.pairingClosed }
        qrConsumed()
        return try await complete(connection, outcome, method: .qr, sessionMethod: .qrPaired)
    }

    // MARK: XX + SAS

    private func acceptSas(_ connection: ControlConnection, _ clock: HandshakeClock) async throws -> AuthenticatedPeer {
        guard limiter.allows() else { throw TransportError.pairingLimited }
        guard case .commit(let commitment) = try await connection.receiveHandshake(timeoutSeconds: clock.nextTimeout()) else {
            throw TransportError.protocolViolation("cần commit")
        }
        let state = try NoiseSessionBox(pattern: .xx, role: .responder, staticKey: identity.privateKey)
        _ = try state.read(try await connection.nextNoise(clock.nextTimeout()))
        let outcome = try await finish(state, connection: connection, clock: clock, viewerPayload: nil)
        guard outcome.payload.role == .viewer, let nonce = outcome.payload.sasNonce,
              try ShortAuthString.verify(
                  commitment: commitment, ephemeralKey: outcome.remoteEphemeral, staticKey: outcome.remoteStatic, nonce: nonce)
        else { throw TransportError.commitmentMismatch }
        let code = ShortAuthString.format(try ShortAuthString.code(messageTwoHash: outcome.messageTwoHash, nonce: nonce))
        return try await complete(connection, outcome, method: .sas(code: code), sessionMethod: .sasPaired)
    }

    // MARK: Chung

    /// Message 2 (hello host); `viewerPayload` có sẵn (IK, đã nằm trong message 1) hoặc đọc từ message 3; rồi dẫn xuất khoá.
    private func finish(
        _ state: NoiseSessionBox, connection: ControlConnection, clock: HandshakeClock, viewerPayload: [UInt8]?
    ) async throws -> NoiseOutcome {
        let hello = try HandshakePayload(role: .host, deviceName: deviceName).encode()
        try await connection.sendHandshake(.noise(try state.write(payload: hello)))
        let payloadBytes: [UInt8]
        if let viewerPayload { payloadBytes = viewerPayload } else {
            payloadBytes = try state.read(try await connection.nextNoise(clock.nextTimeout()))
        }
        guard let remoteStatic = state.remoteStaticKey, let remoteEphemeral = state.remoteEphemeralKey,
              let messageTwoHash = state.messageTwoHash else { throw CryptoError.handshakeIncomplete }
        return NoiseOutcome(
            keys: try state.sessionKeys(), remoteStatic: remoteStatic, remoteEphemeral: remoteEphemeral,
            messageTwoHash: messageTwoHash, payload: try HandshakePayload.decode(payloadBytes))
    }

    /// XXpsk3/XX: hỏi người dùng, ghi thiết bị, báo `pair.result`.
    private func complete(
        _ connection: ControlConnection, _ outcome: NoiseOutcome, method: PairingRequest.Method, sessionMethod: AuthenticatedPeer.Method
    ) async throws -> AuthenticatedPeer {
        await connection.installSession(keys: outcome.keys)
        let request = PairingRequest(
            method: method, deviceName: outcome.payload.deviceName, deviceId: DeviceFingerprint.make(publicKey: outcome.remoteStatic),
            publicKey: outcome.remoteStatic)
        emit(.pairingPending(request))
        guard case .approve(let permissions) = await decide(request) else {
            emit(.pairingResolved(deviceId: request.deviceId, accepted: false))
            _ = try? await connection.send(.pairResult(PairResult(accepted: false)))
            throw TransportError.pairingDenied
        }
        try await store.add(name: request.deviceName, publicKey: request.publicKey, role: .viewer)
        try await store.setPermissions(id: request.deviceId, permissions)
        try await connection.send(.pairResult(PairResult(accepted: true)))
        emit(.pairingResolved(deviceId: request.deviceId, accepted: true))
        let peer = AuthenticatedPeer(
            publicKey: request.publicKey, name: request.deviceName, role: .viewer, permissions: permissions, method: sessionMethod)
        await connection.setPeer(peer)
        await authenticated(peer)
        return peer
    }
}

extension ControlConnection {
    /// Đọc đúng một message Noise.
    func nextNoise(_ timeoutSeconds: Double) async throws -> [UInt8] {
        guard case .noise(let message) = try await receiveHandshake(timeoutSeconds: timeoutSeconds) else {
            throw TransportError.protocolViolation("cần message Noise")
        }
        return message
    }
}
