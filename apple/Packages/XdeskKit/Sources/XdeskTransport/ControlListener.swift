import Foundation
import Network
import XdeskWire

/// Nghe kết nối điều khiển TCP, quảng bá Bonjour, giới hạn số viewer đồng thời.
/// Kết nối thứ N+1 nhận `reject{reason:"busy"}` rồi bị đóng; peer ngoài LAN/loopback bị bỏ ngay.
public actor ControlListener {
    public static let defaultMaxViewers = 4
    public static let busyReason = "busy"

    /// Kết nối đã vào (TCP ready), chưa handshake.
    public nonisolated let connections: AsyncStream<ControlConnection>
    private let continuation: AsyncStream<ControlConnection>.Continuation
    private let security: TransportSecurity
    private let advertiser: BonjourAdvertiser?
    private let maxViewers: Int
    private let queue = DispatchQueue(label: "xdesk.control.listener")
    private var listener: NWListener?
    private var active = 0

    public init(security: TransportSecurity, advertiser: BonjourAdvertiser? = nil, maxViewers: Int = ControlListener.defaultMaxViewers) {
        (connections, continuation) = AsyncStream.makeStream(of: ControlConnection.self)
        self.security = security
        self.advertiser = advertiser
        self.maxViewers = max(1, maxViewers)
    }

    public var activeViewers: Int { active }

    /// Bắt đầu nghe; `port` 0 = cổng ngẫu nhiên. Trả cổng thực.
    public func start(port: UInt16 = 0, loopbackOnly: Bool = false) async throws -> UInt16 {
        try security.requireAvailable()
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
        do {
            return try await startAndAwaitPort(nwListener, queue: queue)
        } catch {
            listener = nil
            throw error
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        continuation.finish()
    }

    private func admit(_ nwConnection: NWConnection) async {
        guard active < maxViewers else {
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
        active += 1
        let conn = ControlConnection(connection: nwConnection, onClose: { [weak self] in
            Task { await self?.released() }
        })
        do {
            try await conn.start()
            continuation.yield(conn)
        } catch {
            await conn.close()
        }
    }

    private func released() { active = max(0, active - 1) }
}
