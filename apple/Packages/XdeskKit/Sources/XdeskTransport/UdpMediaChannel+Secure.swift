import Foundation
import Network
import XdeskCrypto
import XdeskWire

/// Lý do một datagram bị loại trước khi thành gói hợp lệ.
struct DatagramRejection: Error {
    let underlying: CryptoError

    /// Replay/quá cũ là chuyện bình thường của UDP (đảo thứ tự, gói trùng) nên không tính là "bị từ chối".
    var countsAsRejected: Bool { underlying != .replayed && underlying != .outsideReplayWindow }
}

extension UdpMediaChannel {
    /// Đặt hàm gửi `rekey.resync` qua kênh control (do tầng phiên cấp, vì kênh control không thuộc UDP).
    public func setResyncSink(_ sink: (@Sendable (RekeyResync) async -> Void)?) { resyncSink = sink }

    func setLinkTimeout(ms: Int) { linkTimeoutMs = ms }

    /// Epoch gửi hiện tại (nil khi không mã hoá).
    public var sendEpoch: UInt32? { cipher?.sendEpoch }

    /// Message `rekey.resync` từ đối tác (đã xác thực qua TCP): `ask` → trả lời epoch gửi của ta;
    /// không `ask` → kéo khoá nhận lên epoch đối tác đã báo.
    public func handleResync(_ resync: RekeyResync) async {
        guard cipher != nil else { return }
        if resync.ask {
            if let epoch = sendEpoch { await resyncSink?(RekeyResync(epoch: epoch, ask: false)) }
            return
        }
        do {
            try cipher?.resync(toEpoch: resync.epoch)
            recentUnknownEpoch = 0
        } catch {
            malformedPacketCount += 1
        }
    }

    /// Datagram → byte trên dây: seal (reseal cả gói gửi lại) và rekey khi tới hạn, báo epoch mới qua control.
    func datagram(for packet: MediaPacket) throws -> [UInt8] {
        guard cipher != nil else { return try packet.encode() }
        if cipher?.needsRekey == true { try rekeyNow() }
        guard let bytes = try cipher?.seal(packet) else { throw TransportError.encryptionUnavailable }
        return bytes
    }

    /// Đổi khoá gửi sang epoch kế và báo epoch mới qua control (bên nhận tự theo kịp trong 4 epoch, xa hơn thì dựa vào báo này).
    func rekeyNow() throws {
        try cipher?.rekey()
        if let epoch = cipher?.sendEpoch, let sink = resyncSink {
            Task { await sink(RekeyResync(epoch: epoch, ask: false)) }
        }
    }

    func openDatagram(_ bytes: [UInt8]) throws -> MediaPacket {
        guard cipher != nil else { return try MediaPacket.decode(bytes) }
        do {
            guard let packet = try cipher?.open(bytes) else { throw CryptoError.authenticationFailed }
            return packet
        } catch let error as CryptoError {
            if error == .unknownEpoch { recentUnknownEpoch += 1 }
            throw DatagramRejection(underlying: error)
        }
    }

    /// Mã hoá: gói đầu giải mã được biến kết nối ứng viên thành peer; các ứng viên khác bị bỏ.
    func promote(_ conn: NWConnection) {
        guard isEncrypted, !isViewer, peer !== conn else { return }
        peer?.cancel()
        peer = conn
        for other in candidates where other !== conn {
            receiveTasks.removeValue(forKey: ObjectIdentifier(other))?.cancel()
            other.cancel()
        }
        candidates = [conn]
    }

    /// Mỗi giây: giữ liên lạc (probe 2 s/lần), xin đồng bộ epoch nếu chỉ thấy lỗi `unknownEpoch`, và báo mất liên lạc sau 10 s
    /// không có gói hợp lệ (M4: không bao giờ đóng vì gói chưa xác thực).
    func startMaintenance() {
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                await self.maintain()
            }
        }
    }

    private func maintain() async {
        let now = monotonicMs()
        if peer != nil, (isViewer ? heardFromHost : peerAnnounced), now - lastKeepaliveMs >= Self.keepaliveIntervalMs {
            lastKeepaliveMs = now
            try? await transmit(MediaPunch.packet(streamId: streamId))
        }
        if recentUnknownEpoch >= 3, now - lastValidMs >= 2000, now - lastResyncAskMs >= 5000,
           let epoch = cipher?.receiveEpoch, let sink = resyncSink {
            lastResyncAskMs = now
            await sink(RekeyResync(epoch: epoch, ask: true))
        }
        if now - lastValidMs >= linkTimeoutMs, !linkLostReported {
            linkLostReported = true
            continuation.yield(.linkLost)
        }
    }
}
