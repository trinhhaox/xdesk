#if DEBUG
import Testing
import XdeskWire
@testable import XdeskTransport

@Suite struct UdpMediaLoopbackTests {
    private func connectedChannels() async throws -> (pair: ControlPair, viewerChannel: UdpMediaChannel) {
        let pair = try await makeControlPair()
        let viewerChannel = try await UdpMediaChannel.connect(streamId: 7, host: "127.0.0.1", port: pair.viewerResult.ready.udpPort)
        _ = try await collect(pair.hostChannel, count: 1) { if case .peerConnected = $0 { true } else { nil } }
        return (pair, viewerChannel)
    }

    private func shutdown(_ pair: ControlPair, _ viewerChannel: UdpMediaChannel) async {
        await viewerChannel.close(); await pair.hostChannel.close()
        await pair.viewer.close(); await pair.hostConnection.close(); await pair.listener.stop()
    }

    @Test(.timeLimit(.minutes(1))) func nackRecoversDroppedFragmentsAndWholeFrames() async throws {
        let (pair, viewerChannel) = try await connectedChannels()
        // Frame 0 mất mảnh 2; frame 1 mất cả 3 mảnh; frame 2 đến nguyên vẹn và lộ ra khoảng trống.
        let drop = DropPolicy([(0, 2), (1, 0), (1, 1), (1, 2)])
        await pair.hostChannel.setOutgoingFilter { drop.shouldDrop($0) }
        let frames = [pattern(size: 5000, seed: 1), pattern(size: 3000, seed: 2), pattern(size: 4000, seed: 3)]
        for (i, data) in frames.enumerated() {
            try await pair.hostChannel.sendFrame(data, frameNo: UInt32(i), ptsMs: UInt32(i * 16), isKeyframe: i == 0)
        }
        let got = try await collect(viewerChannel, count: 3) { if case .frame(let f) = $0 { f } else { nil } }
        #expect(drop.droppedCount == 4)
        #expect(Set(got.map(\.frameNo)) == [0, 1, 2])
        for f in got {
            #expect(f.data == frames[Int(f.frameNo)])
            #expect(f.isKeyframe == (f.frameNo == 0))
            #expect(f.ptsMs == f.frameNo * 16)
        }
        await shutdown(pair, viewerChannel)
    }

    @Test(.timeLimit(.minutes(1))) func unrecoverableLossRequestsKeyframe() async throws {
        let (pair, viewerChannel) = try await connectedChannels()
        // Frame 0 luôn mất mảnh 1 (kể cả khi gửi lại) → sau 500 ms bộ ghép bỏ frame và đòi keyframe.
        let drop = DropPolicy([(0, 1)], always: true)
        await pair.hostChannel.setOutgoingFilter { drop.shouldDrop($0) }
        try await pair.hostChannel.sendFrame(pattern(size: 2000, seed: 9), frameNo: 0, ptsMs: 0, isKeyframe: true)
        _ = try await collect(viewerChannel, count: 1) { if case .keyframeNeeded = $0 { true } else { nil } }
        await shutdown(pair, viewerChannel)
    }

    @Test(.timeLimit(.minutes(1))) func mediaOverTcpFallbackBypassesUdp() async throws {
        let (pair, viewerChannel) = try await connectedChannels()
        let hostConn = pair.hostConnection
        await pair.hostChannel.setTcpFallback { try await hostConn.sendMediaOverTcp($0) }
        let data = pattern(size: 2500, seed: 4)
        try await pair.hostChannel.sendFrame(data, frameNo: 0, ptsMs: 0, isKeyframe: true)
        var received: [MediaPacket] = []
        while received.count < 3, case .mediaOverTcp(let packet)? = try await pair.viewer.nextInbound() {
            received.append(packet)
            await viewerChannel.ingest(packet)
        }
        let got = try await collect(viewerChannel, count: 1) { if case .frame(let f) = $0 { f } else { nil } }
        #expect(got.first?.data == data)
        await shutdown(pair, viewerChannel)
    }

    @Test(.timeLimit(.minutes(1))) func sendBeforePeerThrows() async throws {
        let channel = try await UdpMediaChannel.listen(streamId: 1)
        await #expect(throws: TransportError.noPeer) {
            try await channel.sendFrame([1, 2, 3], frameNo: 0, ptsMs: 0, isKeyframe: true)
        }
        await channel.close()
    }
}
#endif
