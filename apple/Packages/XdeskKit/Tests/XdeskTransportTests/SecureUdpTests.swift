import CryptoKit
import Foundation
import Network
import Testing
import XdeskCrypto
import XdeskWire
@testable import XdeskTransport

private func fixedKeys(seed: UInt8) -> (send: UdpKeys, receive: UdpKeys) {
    let a = SymmetricKey(data: (0..<32).map { UInt8($0) &+ seed })
    let b = SymmetricKey(data: (0..<32).map { UInt8($0) &+ seed &+ 100 })
    return (UdpKeys(send: a, receive: b), UdpKeys(send: b, receive: a))
}

private func entropyBitsPerByte(_ bytes: [UInt8]) -> Double {
    var counts = [Int](repeating: 0, count: 256)
    for byte in bytes { counts[Int(byte)] += 1 }
    return counts.filter { $0 > 0 }.reduce(0.0) { sum, count in
        let p = Double(count) / Double(bytes.count)
        return sum - p * log2(p)
    }
}

@Suite struct SecureUdpTests {
    private func connected(streamId: UInt16 = 7) async throws -> (host: UdpMediaChannel, viewer: UdpMediaChannel) {
        let keys = fixedKeys(seed: 1)
        let host = try await UdpMediaChannel.listen(streamId: streamId, keys: keys.send)
        let viewer = try await UdpMediaChannel.connect(streamId: streamId, host: "127.0.0.1", port: await host.localPort, keys: keys.receive)
        _ = try await collect(host, count: 1) { if case .peerConnected = $0 { true } else { nil } }
        return (host, viewer)
    }

    @Test(.timeLimit(.minutes(1))) func encryptedFramesFlowAndNackRetransmitsAreResealed() async throws {
        let (host, viewer) = try await connected()
        let drop = DropPolicy([(0, 2), (1, 0), (1, 1), (1, 2)])
        await host.setOutgoingFilter { drop.shouldDrop($0) }
        let frames = [pattern(size: 5000, seed: 1), pattern(size: 3000, seed: 2), pattern(size: 4000, seed: 3)]
        for (i, data) in frames.enumerated() {
            try await host.sendFrame(data, frameNo: UInt32(i), ptsMs: UInt32(i * 16), isKeyframe: i == 0)
        }
        let got = try await collect(viewer, count: 3) { if case .frame(let f) = $0 { f } else { nil } }
        #expect(Set(got.map(\.frameNo)) == [0, 1, 2])
        for f in got { #expect(f.data == frames[Int(f.frameNo)]) }
        #expect(await viewer.rejectedDatagramCount == 0)   // gói gửi lại không bị coi là replay
        await host.close(); await viewer.close()
    }

    @Test(.timeLimit(.minutes(1))) func resendingTheSamePacketProducesDifferentCiphertext() async throws {
        let keys = fixedKeys(seed: 2)
        let channel = try await UdpMediaChannel.listen(streamId: 1, keys: keys.send)
        let packet = MediaPacket(header: MediaHeader(type: .video, streamId: 1, frameNo: 5, fragIdx: 0, fragCnt: 1, isKeyframe: true, ptsMs: 9), payload: pattern(size: 600, seed: 4))
        let first = try await channel.datagram(for: packet)
        let second = try await channel.datagram(for: packet)
        #expect(first != second)
        #expect(Array(first[0..<MediaHeader.size]) == Array(second[0..<MediaHeader.size]))   // header rõ (là AD)
        await channel.close()
    }

    @Test(.timeLimit(.minutes(1))) func ciphertextHidesH264StartCodesAndLooksRandom() async throws {
        let keys = fixedKeys(seed: 3)
        let channel = try await UdpMediaChannel.listen(streamId: 1, keys: keys.send)
        let startCode: [UInt8] = [0, 0, 0, 1]
        var h264 = [UInt8]()
        while h264.count < MediaPacket.maxPayload { h264 += startCode + [0x65] + Array(repeating: 0, count: 60) }
        let payload = Array(h264.prefix(MediaPacket.maxPayload))
        var encrypted: [UInt8] = []
        for frameNo in 0..<200 {
            let header = MediaHeader(type: .video, streamId: 1, frameNo: UInt32(frameNo), fragIdx: 0, fragCnt: 1, isKeyframe: false, ptsMs: 0)
            let datagram = try await channel.datagram(for: MediaPacket(header: header, payload: payload))
            #expect(datagram.count == MediaHeader.size + payload.count + DatagramFormat.overhead)
            encrypted += datagram[(MediaHeader.size + DatagramFormat.nonceLength)...]
        }
        let hasStartCode = encrypted.indices.dropLast(3).contains { encrypted[$0...($0 + 3)].elementsEqual(startCode) }
        #expect(!hasStartCode)
        #expect(entropyBitsPerByte(encrypted) > 7.99)
        await channel.close()
    }

    @Test(.timeLimit(.minutes(1))) func garbageDatagramsAreCountedButNeverCloseTheSession() async throws {
        let (host, viewer) = try await connected()
        let port = try #require(NWEndpoint.Port(rawValue: await host.localPort))
        let attacker = NWConnection(host: "127.0.0.1", port: port, using: .udp)
        try await startAndAwaitReady(attacker, queue: DispatchQueue(label: "test.attacker"))
        for i in 0..<300 {
            attacker.send(content: Data((0..<80).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ i) }), completion: .contentProcessed { _ in })
        }
        #expect(await eventually { await host.rejectedDatagramCount >= 50 })
        // Phiên vẫn dùng được: frame mã hoá thật vẫn tới.
        let data = pattern(size: 2500, seed: 8)
        try await host.sendFrame(data, frameNo: 0, ptsMs: 0, isKeyframe: true)
        let got = try await collect(viewer, count: 1) { if case .frame(let f) = $0 { f } else { nil } }
        #expect(got.first?.data == data)
        attacker.cancel()
        await host.close(); await viewer.close()
    }

    @Test(.timeLimit(.minutes(1))) func silenceBeyondTheTimeoutReportsLinkLostOnlyThen() async throws {
        let keys = fixedKeys(seed: 4)
        let channel = try await UdpMediaChannel.listen(streamId: 1, keys: keys.send)
        await channel.setLinkTimeout(ms: 1500)
        let events = try await collect(channel, count: 1, timeout: .seconds(8)) { if case .linkLost = $0 { true } else { nil } }
        #expect(events == [true])
        await channel.close()
    }

    /// Host khoá màn hình không phát khung hình nào (`host.state videoAvailable:false`): keepalive probe hai chiều phải giữ liên kết sống.
    @Test(.timeLimit(.minutes(1))) func probeKeepaliveAloneKeepsTheLinkAliveWithoutAnyVideoFrame() async throws {
        let (host, viewer) = try await connected()
        await host.setLinkTimeout(ms: 3500)
        await viewer.setLinkTimeout(ms: 3500)
        let lostHost = Task { await (try? collect(host, count: 1, timeout: .seconds(8)) { if case .linkLost = $0 { true } else { nil } }) }
        let lostViewer = Task { await (try? collect(viewer, count: 1, timeout: .seconds(8)) { if case .linkLost = $0 { true } else { nil } }) }
        // Cả hai collect đều hết giờ (throw Timeout → nil) vì không bên nào báo linkLost dù không có khung hình suốt 8 s > 3.5 s.
        #expect(await lostHost.value == nil)
        #expect(await lostViewer.value == nil)
        await host.close(); await viewer.close()
    }

    @Test(.timeLimit(.minutes(1))) func epochGapBeyondLookaheadRecoversThroughResync() async throws {
        let (host, viewer) = try await connected()
        for _ in 0..<(Int(DatagramReceiver.maxEpochLookahead) + 2) { try await host.rekeyNow() }
        let lost = pattern(size: 1500, seed: 5)
        try await host.sendFrame(lost, frameNo: 0, ptsMs: 0, isKeyframe: true)
        #expect(await eventually { await viewer.rejectedDatagramCount >= 2 })

        await viewer.handleResync(RekeyResync(epoch: try #require(await host.sendEpoch), ask: false))
        let data = pattern(size: 1500, seed: 6)
        try await host.sendFrame(data, frameNo: 1, ptsMs: 0, isKeyframe: true)
        let got = try await collect(viewer, count: 1) { if case .frame(let f) = $0, f.frameNo == 1 { f } else { nil } }
        #expect(got.first?.data == data)
        await host.close(); await viewer.close()
    }

    @Test(.timeLimit(.minutes(1))) func askingForResyncAnswersWithTheSendEpoch() async throws {
        let (host, viewer) = try await connected()
        try await host.rekeyNow()
        let answers = ResyncBox()
        await host.setResyncSink { await answers.add($0) }
        await host.handleResync(RekeyResync(epoch: 0, ask: true))
        #expect(await answers.items == [RekeyResync(epoch: 1, ask: false)])
        await host.close(); await viewer.close()
    }
}

actor ResyncBox {
    private(set) var items: [RekeyResync] = []
    func add(_ item: RekeyResync) { items.append(item) }
}
