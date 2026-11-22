import Foundation
import Testing
@testable import XdeskMedia
import XdeskWire

private func sine(frames: Int, startPhase: inout Double) -> [Int16] {
    var out = [Int16]()
    for _ in 0..<frames {
        let v = Int16(sin(startPhase) * 12_000)
        startPhase += 2 * .pi * 440 / 48_000
        out.append(v)
        out.append(v)
    }
    return out
}

@Suite struct AudioCodecTests {
    @Test func policyPicksPcmOnLanAndAacOnNarrowPath() throws {
        let both: Capabilities = [.audioPCM, .audioAACELD]
        var lan = try #require(AudioCodecPolicy(negotiated: both, narrowPath: false))
        #expect(lan.codec == .pcm)
        #expect(lan.update(estimateKbps: 9_999) == .aacEld)
        #expect(lan.update(estimateKbps: 11_000) == .aacEld, "vùng trễ 10–12 Mb/s giữ nguyên")
        #expect(lan.update(estimateKbps: 12_000) == .pcm)
        var tailscale = try #require(AudioCodecPolicy(negotiated: both, narrowPath: true))
        #expect(tailscale.update(estimateKbps: 40_000) == .aacEld)
        #expect(AudioCodecPolicy(negotiated: [.h264], narrowPath: false) == nil)
    }

    @Test func policyHonoursViewerSupport() throws {
        var pcmOnly = try #require(AudioCodecPolicy(negotiated: [.audioPCM], narrowPath: true))
        #expect(pcmOnly.update(estimateKbps: 1_000) == .pcm)
        var aacOnly = try #require(AudioCodecPolicy(negotiated: [.audioAACELD], narrowPath: false))
        #expect(aacOnly.update(estimateKbps: 40_000) == .aacEld)
    }

    @Test func encoderCookieCarriesFixedAudioSpecificConfig() throws {
        let cookie = try #require(try AacEldEncoder().magicCookie)
        let asc = AudioPayload.aacEldConfig
        #expect(cookie.indices.dropLast(asc.count - 1).contains { Array(cookie[$0..<$0 + asc.count]) == asc })
    }

    @Test func aacEldRoundTripPreservesTone() throws {
        let encoder = try AacEldEncoder()
        let decoder = try AacEldDecoder()
        var phase = 0.0
        var decodedPeak = 0
        var units = 0
        for _ in 0..<40 {
            guard let unit = try encoder.encode(sine(frames: 512, startPhase: &phase)) else { continue }
            units += 1
            #expect(unit.count < 400, "96 kb/s ≈ 128 B mỗi 10,7 ms")
            let pcm = try decoder.decode(unit)
            #expect(pcm.count == 1024)
            decodedPeak = max(decodedPeak, pcm.map { abs(Int($0)) }.max() ?? 0)
        }
        #expect(units >= 39)
        #expect(decodedPeak > 8_000)
    }

    @Test func decoderRejectsGarbage() throws {
        let decoder = try AacEldDecoder()
        #expect(throws: AudioCodecError.self) { try decoder.decode([]) }
    }

    @Test func packetizerRechunksAndStampsPts() throws {
        var packetizer = AudioPacketizer(streamId: 3)
        var phase = 0.0
        var packets: [MediaPacket] = []
        // SCK gửi khối 1024 mẫu: 3 khối = 3072 mẫu = 12 gói 240 + dư 192.
        for i in 0..<3 {
            let capture = 1000 + Double(i * 1024) * 1000 / 48_000
            packets += try packetizer.push(samples: sine(frames: 1024, startPhase: &phase), captureMs: capture, nowMs: capture + 7, codec: .pcm)
        }
        #expect(packets.count == 12)
        #expect(packets.map(\.header.frameNo) == Array(0..<12))
        #expect(packets[0].header.ptsMs == 1000)
        #expect(packets[1].header.ptsMs == 1005)
        #expect(packets[11].header.ptsMs == 1055)
        let first = try AudioPayload.decode(packets[0].payload)
        #expect(first.codec == .pcm && first.data.count == 960 && first.holdMs == 7)
        #expect(AudioPacketizer.samples(fromLittleEndian: first.data).count == 480)
    }

    @Test func packetizerReanchorsAfterGapAndSwitchesCodec() throws {
        var packetizer = AudioPacketizer(streamId: 1)
        var phase = 0.0
        _ = try packetizer.push(samples: sine(frames: 480, startPhase: &phase), captureMs: 0, nowMs: 1, codec: .pcm)
        let afterGap = try packetizer.push(samples: sine(frames: 480, startPhase: &phase), captureMs: 500, nowMs: 501, codec: .pcm)
        #expect(afterGap.first?.header.ptsMs == 500)
        var aac: [MediaPacket] = []
        for i in 0..<6 {
            aac += try packetizer.push(samples: sine(frames: 512, startPhase: &phase), captureMs: 510 + Double(i) * 10.667, nowMs: 520, codec: .aacEld)
        }
        #expect(!aac.isEmpty)
        #expect(try aac.allSatisfy { try AudioPayload.decode($0.payload).codec == .aacEld })
    }

    @Test func audioPlayerMuteTogglesSafely() {
        let player = AudioPlayer()
        #expect(!player.isMuted)
        player.isMuted = true
        #expect(player.isMuted)
        player.isMuted = false
        #expect(!player.isMuted)
    }
}
