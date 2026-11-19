import Foundation
import Network
import XdeskWire

/// Nghe kết nối điều khiển TCP, quảng bá Bonjour, giới hạn số viewer đồng thời.
/// Chế độ plaintext (Debug): kết nối thứ N+1 nhận `reject{reason:"busy"}` rồi bị đóng.
/// Chế độ mã hoá: listener tự chạy bắt tay Noise (`HostAuthenticator`) và chỉ trao ra kết nối đã xác thực; kết nối chưa xác thực
/// bị giới hạn mỗi IP nguồn `maxPendingPerSource` (2), tối đa `maxPending` (4) cùng lúc (đầy thì đuổi kết nối cũ nhất) (M5).
/// Peer ngoài LAN/loopback bị bỏ ngay; peer Tailscale (100.64/10, fd7a:115c:a1e0::/48) chỉ được nhận khi `allowTailscale` (mặc định tắt).
public actor ControlListener {
    public static let defaultMaxViewers = 4
    public static let busyReason = "busy"
    public static let defaultMaxPending = 4
    public static let defaultMaxPendingPerSource = 2

    private struct Entry {
        let connection: ControlConnection
        let source: String
        let startedAt: ContinuousClock.Instant
        var authenticated: Bool
    }

    /// Kết nối đã vào, đã xác thực (mã hoá) hoặc mới TCP-ready (plaintext), chưa hello/welcome.
    public nonisolated let connections: AsyncStream<ControlConnection>
    private let continuation: AsyncStream<ControlConnection>.Continuation
    let security: TransportSecurity
    private let advertiser: BonjourAdvertiser?
    let authenticator: HostAuthenticator?
    private let maxViewers: Int
    private let maxPending: Int
    private let maxPendingPerSource: Int
    private let queue = DispatchQueue(label: "xdesk.control.listener")
    var listener: NWListener?
    private var entries: [UUID: Entry] = [:]
    private var allowTailscale: Bool
    private let isTailscale: @Sendable (NWEndpoint) -> Bool

    public init(
        security: TransportSecurity, advertiser: BonjourAdvertiser? = nil, authenticator: HostAuthenticator? = nil,
        maxViewers: Int = ControlListener.defaultMaxViewers, maxPending: Int = ControlListener.defaultMaxPending,
        maxPendingPerSource: Int = ControlListener.defaultMaxPendingPerSource, allowTailscale: Bool = false,
        tailscaleClassifier: @escaping @Sendable (NWEndpoint) -> Bool = { InterfaceFilter.isTailscale($0) }
    ) {
        self.allowTailscale = allowTailscale
        self.isTailscale = tailscaleClassifier
        (connections, continuation) = AsyncStream.makeStream(of: ControlConnection.self)
        self.security = security
        self.advertiser = advertiser
        self.authenticator = authenticator
        self.maxViewers = max(1, maxViewers)
        self.maxPending = max(1, maxPending)
        self.maxPendingPerSource = max(1, maxPendingPerSource)
    }

    /// Bật/tắt nhận kết nối qua Tailscale (chỉ áp dụng cho kết nối mới; phiên đang chạy giữ nguyên).
    public func setAllowTailscale(_ allowed: Bool) { allowTailscale = allowed }

    /// Số viewer đang giữ chỗ (đã xác thực, hoặc plaintext).
    public var activeViewers: Int { entries.values.filter(\.authenticated).count }
    public var pendingHandshakes: Int { entries.values.filter { !$0.authenticated }.count }

    /// Bắt đầu nghe; `port` 0 = cổng ngẫu nhiên. Trả cổng thực.
    public func start(port: UInt16 = 0, loopbackOnly: Bool = false) async throws -> UInt16 {
        try security.requireAvailable()
        if security == .encrypted, authenticator == nil { throw TransportError.encryptionUnavailable }
        guard listener == nil else { throw TransportError.listenerFailed("already started") }
        let params = NWParameters.tcp
        if loopbackOnly { params.requiredInterfaceType = .loopback }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw TransportError.listenerFailed("bad port") }
        let nwListener: NWListener
        do {
            nwListener = try NWListener(using: params, on: nwPort)
        } catch {
            throw TransportError.listenerFailed("\(error)")
        }
        nwListener.service = advertiser?.service
        nwListener.newConnectionHandler = { [weak self] connection in
            guard PeerAddressPolicy.isAllowed(connection.endpoint) else { connection.cancel(); return }
            Task { await self?.admit(connection) }
        }
        listener = nwListener
        await authenticator?.start()
        do {
            return try await startAndAwaitPort(nwListener, queue: queue)
        } catch {
            listener = nil
            throw error
        }
    }

    public func stop() async {
        listener?.cancel()
        listener = nil
        continuation.finish()
        await authenticator?.stop()
        for entry in entries.values { await entry.connection.close() }
    }

    private func admit(_ nwConnection: NWConnection) async {
        guard allowTailscale || !isTailscale(nwConnection.endpoint) else {
            nwConnection.cancel()
            return
        }
        if security == .encrypted, let authenticator {
            await admitSecure(nwConnection, authenticator)
        } else {
            await admitPlain(nwConnection)
        }
    }

    // MARK: Plaintext (Debug)

    private func admitPlain(_ nwConnection: NWConnection) async {
        guard activeViewers < maxViewers else {
            let busy = ControlConnection(connection: nwConnection)
            do {
                try await busy.start()
                try await busy.send(.reject(Reject(reason: Self.busyReason, detail: "max \(maxViewers) viewers")), id: 0)
            } catch {
                // Viewer đã rời trước khi nhận reject; không còn gì để báo.
            }
            await busy.close()
            return
        }
        let id = UUID()
        let conn = ControlConnection(connection: nwConnection, onClose: { [weak self] in
            Task { await self?.released(id) }
        })
        entries[id] = Entry(connection: conn, source: Self.source(of: nwConnection), startedAt: .now, authenticated: true)
        do {
            try await conn.start()
            continuation.yield(conn)
        } catch {
            await conn.close()
        }
    }

    // MARK: Mã hoá

    func admitSecure(_ nwConnection: NWConnection, _ authenticator: HostAuthenticator, usbHello: [UInt8]? = nil) async {
        let source = usbHello == nil ? Self.source(of: nwConnection) : "usb"
        guard entries.values.filter({ !$0.authenticated && $0.source == source }).count < maxPendingPerSource else {
            nwConnection.cancel()
            return
        }
        if pendingHandshakes >= maxPending, let oldest = entries.values.filter({ !$0.authenticated }).min(by: { $0.startedAt < $1.startedAt }) {
            await oldest.connection.close()
        }
        let id = UUID()
        let onClose: @Sendable () -> Void = { [weak self] in Task { await self?.released(id) } }
        let conn = usbHello == nil
            ? ControlConnection(connection: nwConnection, encrypted: true, onClose: onClose)
            : ControlConnection.adoptUsbTunnel(nwConnection, onClose: onClose)
        entries[id] = Entry(connection: conn, source: source, startedAt: .now, authenticated: false)
        do {
            if let usbHello { try await conn.sendUsbHello(hostPublicKey: usbHello) } else { try await conn.start() }
            let peer = try await authenticator.accept(conn)
            try await promote(id, conn, peer, authenticator)
        } catch {
            await conn.close()
        }
    }

    private func promote(_ id: UUID, _ conn: ControlConnection, _ peer: AuthenticatedPeer, _ authenticator: HostAuthenticator) async throws {
        guard var entry = entries[id] else { throw TransportError.connectionClosed }
        // IK: chưa phải "viewer đang hiện diện" tới khi có frame mã hoá hợp lệ đầu tiên (M6) → vẫn tính vào hàng chờ chưa xác thực.
        entry.authenticated = peer.method != .reconnect
        guard activeViewers < maxViewers || !entry.authenticated else {
            _ = try? await conn.send(.reject(Reject(reason: Self.busyReason, detail: "max \(maxViewers) viewers")), id: 0)
            throw TransportError.rejected(reason: Self.busyReason, detail: nil)
        }
        entries[id] = entry
        await authenticator.register(id: id, connection: conn, deviceId: peer.deviceId)
        if peer.method == .reconnect {
            await conn.addFirstFrameHook { [weak self] in await self?.confirmAuthenticated(id) }
        }
        continuation.yield(conn)
    }

    private func confirmAuthenticated(_ id: UUID) async {
        guard var entry = entries[id], !entry.authenticated else { return }
        guard activeViewers < maxViewers else {
            _ = try? await entry.connection.send(.reject(Reject(reason: Self.busyReason, detail: "max \(maxViewers) viewers")), id: 0)
            await entry.connection.close()
            return
        }
        entry.authenticated = true
        entries[id] = entry
    }

    private func released(_ id: UUID) async {
        guard entries.removeValue(forKey: id) != nil else { return }
        await authenticator?.unregister(id: id)
    }

    private static func source(of connection: NWConnection) -> String {
        connection.endpoint.hostPort.map { PeerAddressPolicy.normalized($0) } ?? "?"
    }
}
