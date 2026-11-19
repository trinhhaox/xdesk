import Foundation
import Network
import XdeskCrypto
import XdeskWire

/// Kênh media UDP một viewer ↔ một host.
/// Host: `listen` rồi gửi `display.ready{udpPort}`; viewer: `connect` và gửi `probe` (ptype 0x50) định kỳ tới khi nhận được gói
/// đầu tiên để host biết địa chỉ. Gửi: cắt gói + giữ lịch sử để trả lời NACK. Nhận: ghép frame, tự NACK,
/// phát `.keyframeNeeded` khi phải bỏ frame (người gọi gửi `keyframe.request` qua control).
/// Có `keys` (Noise) thì mọi datagram được mã hoá (`UdpCipher`); lỗi giải mã chỉ bị đếm, không bao giờ đóng kênh (M4);
/// kênh phát `.linkLost` khi 10 s không có gói hợp lệ nào.
public actor UdpMediaChannel {
    public enum Event: Sendable, Equatable {
        case peerConnected
        case frame(AssembledFrame)
        case keyframeNeeded
        /// Gói không phải video/NACK (input, audio...) cho tầng trên.
        case packet(MediaPacket)
        /// Không có gói hợp lệ suốt `linkTimeoutMs`.
        case linkLost
    }

    static let punchIntervalMs = 250
    static let pollIntervalMs = 10
    static let keepaliveIntervalMs = 2000
    static let linkTimeoutMs = 10_000
    static let maxCandidates = 4

    public nonisolated let events: AsyncStream<Event>
    public let streamId: UInt16
    public private(set) var localPort: UInt16 = 0
    public internal(set) var malformedPacketCount = 0
    /// Datagram bị loại vì tag/epoch/độ dài sai (chưa xác thực); chỉ để đo, không dẫn tới đóng kênh.
    public internal(set) var rejectedDatagramCount = 0

    let continuation: AsyncStream<Event>.Continuation
    let queue = DispatchQueue(label: "xdesk.udp.media")
    let packetizer: Packetizer
    let allowedPeerHost: String?
    var peer: NWConnection?
    var candidates: [NWConnection] = []
    var listener: NWListener?
    var history = MediaSendHistory()
    var reassembler = Reassembler()
    var nackTracker = NackTracker()
    var pollTask: Task<Void, Never>?
    var maintenanceTask: Task<Void, Never>?
    var receiveTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    var heardFromHost = false
    var peerAnnounced = false
    var lastPunchMs = 0
    var lastKeepaliveMs = 0
    var lastValidMs = monotonicMs()
    var lastResyncAskMs = 0
    var recentUnknownEpoch = 0
    var linkLostReported = false
    var linkTimeoutMs = UdpMediaChannel.linkTimeoutMs
    var isViewer = false
    var closed = false
    var cipher: UdpCipher?
    var resyncSink: (@Sendable (RekeyResync) async -> Void)?
    var tcpSink: (@Sendable (MediaPacket) async throws -> Void)?
    var outgoingFilter: (@Sendable (MediaPacket) -> Bool)?

    init(streamId: UInt16, allowedPeerHost: String?, keys: UdpKeys?) {
        (events, continuation) = AsyncStream.makeStream(of: Event.self)
        self.streamId = streamId
        self.packetizer = Packetizer(streamId: streamId)
        self.allowedPeerHost = allowedPeerHost
        self.cipher = keys.map { UdpCipher(keys: $0) }
    }

    var isEncrypted: Bool { cipher != nil }

    // MARK: Khởi tạo

    /// Host: nghe UDP; `allowedPeerHost` (host của kết nối TCP) giới hạn peer nhận media.
    public static func listen(
        streamId: UInt16, port: UInt16 = 0, allowedPeerHost: NWEndpoint.Host? = nil, keys: UdpKeys? = nil
    ) async throws -> UdpMediaChannel {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw TransportError.listenerFailed("bad port") }
        let channel = UdpMediaChannel(streamId: streamId, allowedPeerHost: allowedPeerHost.map(PeerAddressPolicy.normalized), keys: keys)
        try await channel.startListening(port: nwPort)
        return channel
    }

    /// Viewer: trỏ tới `host:port` do `display.ready` báo.
    public static func connect(streamId: UInt16, host: NWEndpoint.Host, port: UInt16, keys: UdpKeys? = nil) async throws -> UdpMediaChannel {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw TransportError.connectionFailed("port 0") }
        let channel = UdpMediaChannel(streamId: streamId, allowedPeerHost: nil, keys: keys)
        try await channel.startConnecting(host: host, port: nwPort)
        return channel
    }

    private func startListening(port: NWEndpoint.Port) async throws {
        let nwListener: NWListener
        do { nwListener = try NWListener(using: .udp, on: port) } catch { throw TransportError.listenerFailed("\(error)") }
        nwListener.newConnectionHandler = { [weak self] conn in Task { await self?.adopt(conn) } }
        listener = nwListener
        localPort = try await startAndAwaitPort(nwListener, queue: queue)
        startMaintenance()
    }

    private func startConnecting(host: NWEndpoint.Host, port: NWEndpoint.Port) async throws {
        isViewer = true
        let conn = NWConnection(host: host, port: port, using: .udp)
        try await startAndAwaitReady(conn, queue: queue)
        peer = conn
        beginReceiving(on: conn)
        startPolling()
        startMaintenance()
    }

    func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: .milliseconds(Self.pollIntervalMs))
            }
        }
    }

    /// Plaintext: peer mới thay peer cũ (cùng IP). Mã hoá: chỉ nhận làm ứng viên, thành peer khi giải mã được gói đầu (`promote`).
    private func adopt(_ conn: NWConnection) async {
        let host = conn.endpoint.hostPort.map { PeerAddressPolicy.normalized($0) }
        let replaceable = allowedPeerHost != nil && allowedPeerHost == host
        let free = isEncrypted ? candidates.count < Self.maxCandidates : (peer == nil || replaceable)
        guard !closed, free, allowedPeerHost == nil || allowedPeerHost == host,
              PeerAddressPolicy.isAllowed(conn.endpoint) else { conn.cancel(); return }
        do { try await startAndAwaitReady(conn, queue: queue) } catch { conn.cancel(); return }
        if isEncrypted {
            candidates.append(conn)
        } else {
            if let old = peer { receiveTasks.removeValue(forKey: ObjectIdentifier(old))?.cancel(); old.cancel() }
            peer = conn
        }
        beginReceiving(on: conn)
    }

    // MARK: Gửi

    /// Hook MediaOverTcp: khi đặt, mọi gói đi qua sink (vd. `ControlConnection.sendMediaOverTcp`) thay vì UDP.
    public func setTcpFallback(_ sink: (@Sendable (MediaPacket) async throws -> Void)?) { tcpSink = sink }

    func setOutgoingFilter(_ filter: (@Sendable (MediaPacket) -> Bool)?) { outgoingFilter = filter }

    /// Cắt một access unit (Annex B) thành gói và gửi.
    public func sendFrame(_ accessUnit: [UInt8], frameNo: UInt32, ptsMs: UInt32, isKeyframe: Bool) async throws {
        let packets = try packetizer.packetize(frame: accessUnit, frameNo: frameNo, ptsMs: ptsMs, isKeyframe: isKeyframe)
        history.store(frameNo: frameNo, packets: packets)
        for packet in packets { try await transmit(packet) }
    }

    public func sendPacket(_ packet: MediaPacket) async throws { try await transmit(packet) }

    func transmit(_ packet: MediaPacket) async throws {
        if let tcpSink { try await tcpSink(packet); return }
        guard let peer else { throw TransportError.noPeer }
        if outgoingFilter?(packet) == true { return }
        let bytes = try datagram(for: packet)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            peer.send(content: Data(bytes), completion: .contentProcessed { error in
                if let error { cont.resume(throwing: TransportError.connectionFailed("\(error)")) } else { cont.resume() }
            })
        }
    }

    public func close() {
        guard !closed else { return }
        closed = true
        pollTask?.cancel()
        maintenanceTask?.cancel()
        receiveTasks.values.forEach { $0.cancel() }
        receiveTasks.removeAll()
        peer?.cancel()
        candidates.forEach { $0.cancel() }
        listener?.cancel()
        continuation.finish()
    }
}

extension NWEndpoint {
    var hostPort: NWEndpoint.Host? {
        if case .hostPort(let host, _) = self { return host }
        return nil
    }
}
