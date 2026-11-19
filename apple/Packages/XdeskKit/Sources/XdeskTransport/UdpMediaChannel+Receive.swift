import Foundation
import Network
import XdeskWire

extension UdpMediaChannel {
    // MARK: Nhận

    /// Đưa vào gói nhận được qua đường khác (MediaOverTcp).
    public func ingest(_ packet: MediaPacket) async {
        heardFromHost = true
        lastValidMs = monotonicMs()
        await handle(packet)
    }

    func beginReceiving(on conn: NWConnection) {
        let key = ObjectIdentifier(conn)
        receiveTasks[key] = Task { [weak self] in
            while !Task.isCancelled {
                guard let data = await Self.receiveDatagram(conn) else { return }
                guard let self else { return }
                await self.handleDatagram(data, from: conn)
            }
        }
    }

    private static func receiveDatagram(_ conn: NWConnection) async -> [UInt8]? {
        await withCheckedContinuation { cont in
            conn.receiveMessage { data, _, _, error in
                cont.resume(returning: error == nil ? data.map { [UInt8]($0) } ?? [] : nil)
            }
        }
    }

    private func handleDatagram(_ bytes: [UInt8], from conn: NWConnection) async {
        guard !bytes.isEmpty else { return }
        do {
            let packet = try openDatagram(bytes)
            lastValidMs = monotonicMs()
            recentUnknownEpoch = 0
            linkLostReported = false
            promote(conn)
            if isViewer { heardFromHost = true }
            await handle(packet)
        } catch let error as DatagramRejection {
            if error.countsAsRejected { rejectedDatagramCount += 1 }
        } catch {
            malformedPacketCount += 1
        }
    }

    func handle(_ packet: MediaPacket) async {
        if packet.header.type == .probe {
            if !isViewer, MediaPunch.isProbe(packet), !peerAnnounced {
                peerAnnounced = true
                continuation.yield(.peerConnected)
            }
            return
        }
        switch packet.header.type {
        case .video where packet.header.streamId == streamId:
            do {
                if let frame = try reassembler.ingest(packet, nowMs: monotonicMs()) { continuation.yield(.frame(frame)) }
            } catch {
                malformedPacketCount += 1
            }
        case .nack where packet.header.streamId == streamId:
            await resend(for: packet)
        case .video, .nack:
            break
        default:
            continuation.yield(.packet(packet))
        }
    }

    private func resend(for nack: MediaPacket) async {
        guard let entries = try? NackPayload.decode(nack.payload) else { malformedPacketCount += 1; return }
        for entry in entries {
            for packet in history.packets(for: entry) { try? await transmit(packet) }
        }
    }

    /// Mỗi 10 ms: punch (nếu chưa nghe được host) và NACK/bỏ frame.
    func tick() async {
        let now = monotonicMs()
        if !heardFromHost, now - lastPunchMs >= Self.punchIntervalMs {
            lastPunchMs = now
            try? await transmit(MediaPunch.packet(streamId: streamId))
        }
        let poll = nackTracker.poll(&reassembler, nowMs: now)
        if !poll.nacks.isEmpty, let nack = try? MediaPacket.nack(streamId: streamId, entries: poll.nacks) {
            try? await transmit(nack)
        }
        if !poll.abandoned.isEmpty { continuation.yield(.keyframeNeeded) }
    }
}
