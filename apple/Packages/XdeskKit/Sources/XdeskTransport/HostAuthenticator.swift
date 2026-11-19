import Foundation
import XdeskCrypto
import XdeskWire

/// Chính sách xác thực phía host (responder): danh tính, danh sách thiết bị đã ghép, token QR, giới hạn SAS,
/// sổ phiên đang chạy (để thu hồi cắt phiên ≤ 1 s) và sự kiện cho UI. `ControlListener` gọi `accept` cho từng kết nối mới.
public actor HostAuthenticator {
    public static let decisionTimeoutSeconds = 60.0
    public static let defaultQrRotationSeconds = 20.0

    public nonisolated let events: AsyncStream<HostAuthEvent>
    let continuation: AsyncStream<HostAuthEvent>.Continuation
    let identity: DeviceIdentity
    let deviceName: String
    let store: PairedDevicesStore
    var issuer = PairingTokenIssuer()
    var limiter = SasFailureLimiter()
    var decider: PairingDecider = { _ in .reject }
    private var live: [UUID: (deviceId: String, connection: ControlConnection)] = [:]
    private let qrRotationSeconds: Double
    private var qrAddresses: [String] = []
    private var qrIssuedAt = Date.distantPast
    private var qrTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?

    public init(
        identity: DeviceIdentity, deviceName: String, store: PairedDevicesStore,
        qrRotationSeconds: Double = HostAuthenticator.defaultQrRotationSeconds
    ) {
        self.qrRotationSeconds = qrRotationSeconds
        (events, continuation) = AsyncStream.makeStream(of: HostAuthEvent.self)
        self.identity = identity
        self.deviceName = deviceName
        self.store = store
    }

    /// Gắn hook UI quyết định ghép đôi.
    public func setPairingDecider(_ decider: @escaping PairingDecider) { self.decider = decider }

    public var fingerprint: String { identity.fingerprint }
    public var publicKey: [UInt8] { identity.publicKey }
    public var liveSessionCount: Int { live.count }

    // MARK: Vòng đời

    /// Bắt đầu theo dõi danh sách thiết bị: xoá thiết bị → cắt ngay phiên của nó.
    func start() async {
        guard watchTask == nil else { return }
        let changes = await store.changes()
        watchTask = Task { [weak self] in
            for await change in changes {
                if case .removed(let id) = change { await self?.revoke(deviceId: id) }
            }
        }
    }

    func stop() {
        watchTask?.cancel()
        watchTask = nil
        stopQrPairing()
    }

    // MARK: Sổ phiên và thu hồi

    func register(id: UUID, connection: ControlConnection, deviceId: String) {
        live[id] = (deviceId, connection)
    }

    func unregister(id: UUID) {
        guard let entry = live.removeValue(forKey: id) else { return }
        continuation.yield(.sessionClosed(deviceId: entry.deviceId))
    }

    private func revoke(deviceId: String) async {
        let doomed = live.values.filter { $0.deviceId == deviceId }.map(\.connection)
        guard !doomed.isEmpty else { return }
        continuation.yield(.sessionRevoked(deviceId: deviceId))
        for connection in doomed {
            // Báo viewer (kênh đã mã hoá) để nó quên host này; viewer đã mất kết nối thì bỏ qua, phiên vẫn bị cắt.
            _ = try? await connection.send(.reject(Reject(reason: Reject.reasonRevoked)), id: 0)
            await connection.close()
        }
    }

    /// Thu hồi một thiết bị: xoá khỏi danh sách (việc cắt phiên do `start()` theo dõi, xong trong vài ms).
    @discardableResult
    public func revokeDevice(id: String) async throws -> Bool { try await store.remove(id: id) }

    /// Phiên đã xác thực thật sự (IK: sau frame mã hoá hợp lệ đầu tiên; ghép đôi: sau khi host duyệt).
    func authenticated(_ peer: AuthenticatedPeer) async {
        try? await store.markSeen(id: peer.deviceId)
        continuation.yield(.sessionOpened(peer))
    }

    func emit(_ event: HostAuthEvent) { continuation.yield(event) }

    // MARK: QR

    /// Phát token QR mới (vô hiệu token cũ). Khi có phiên đang chạy, token tự đổi mỗi `qrRotationSeconds` để người xem
    /// màn hình (kể cả viewer chỉ-xem, ghi hình) không kịp dùng; hết hạn không dùng → `qrClosed(.expired)`.
    @discardableResult
    public func startQrPairing(addresses: [String]) throws -> PairingURI {
        qrAddresses = addresses
        let uri = try issueQr()
        qrTask?.cancel()
        qrTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, await self.tickQr() else { return }
            }
        }
        return uri
    }

    public func stopQrPairing() {
        qrTask?.cancel()
        qrTask = nil
        if issuer.activeToken() != nil { continuation.yield(.qrClosed(.cancelled)) }
        issuer.invalidate()
    }

    private func issueQr() throws -> PairingURI {
        let token = try issuer.issue()
        qrIssuedAt = Date()
        let uri = try PairingURI(hostPublicKey: identity.publicKey, token: token.bytes, addresses: qrAddresses)
        continuation.yield(.qrIssued(uri))
        return uri
    }

    /// `false` khi vòng QR kết thúc.
    private func tickQr() -> Bool {
        guard issuer.activeToken() != nil else {
            continuation.yield(.qrClosed(.expired))
            return false
        }
        if !live.isEmpty, Date().timeIntervalSince(qrIssuedAt) >= qrRotationSeconds { _ = try? issueQr() }
        return true
    }

    func qrConsumed() {
        qrTask?.cancel()
        qrTask = nil
        continuation.yield(.qrClosed(.paired))
    }

    func qrFailed() {
        if issuer.recordFailure() {
            qrTask?.cancel()
            qrTask = nil
            continuation.yield(.qrClosed(.tooManyFailures))
        }
    }

    // MARK: Quyết định của người dùng

    func decide(_ request: PairingRequest) async -> PairingDecision {
        let decide = decider
        return await withTaskGroup(of: PairingDecision.self) { group in
            group.addTask { await decide(request) }
            group.addTask {
                try? await Task.sleep(for: .seconds(Self.decisionTimeoutSeconds))
                return .reject
            }
            let first = await group.next() ?? .reject
            group.cancelAll()
            return first
        }
    }
}
