import AVFoundation
import Foundation
import os
import XdeskWire

/// Số liệu phát audio ở viewer (cập nhật theo yêu cầu, không phải callback thời gian thực).
public struct AudioPlaybackStats: Sendable, Equatable {
    public var packets = 0
    public var malformed = 0
    public var codec: AudioWireCodec?
    /// Độ sâu jitter buffer hiện tại (ms).
    public var jitterDepthMs = 0
    public var underruns = 0
    public var concealedFrames = 0
    /// Độ trễ phần cứng phát ra (ms).
    public var outputLatencyMs = 0
    /// Host giữ đoạn mới nhất bao lâu từ lúc ghi tới lúc gửi (ms).
    public var hostHoldMs = 0
    /// Biên độ lớn nhất (|mẫu|, 0…32767) của gói nhận gần nhất; dùng đo/hiển thị mức.
    public var lastPeak = 0
    /// Số lần có tiếng sau im lặng (biên độ > 3000 sau ≥ 50 ms yên) và giờ Unix (ms) của lần gần nhất — dùng đo trễ miệng-tai.
    public var onsets = 0
    public var lastOnsetUnixMs: Int64 = 0

    public init() {}

    /// Ước lượng trễ đầu-cuối: host giữ + mạng một chiều (rtt/2) + jitter buffer + thiết bị phát.
    public func estimatedLatencyMs(rttMs: Int) -> Int { hostHoldMs + rttMs / 2 + jitterDepthMs + outputLatencyMs }
}

/// Phát audio nhận được: giải mã PCM/AAC-ELD → `AudioJitterBuffer` (40 ms) → `AVAudioEngine`.
/// `ingest` gọi từ một luồng; callback render chạy trên luồng audio của hệ thống.
public final class AudioPlayer: @unchecked Sendable {
    private struct State {
        var jitter = AudioJitterBuffer()
        var stats = AudioPlaybackStats()
        var quietPackets = 0
        var muted = false
    }

    private static let onsetPeak = 3_000
    private static let onsetQuietPackets = 10
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var decoder: AacEldDecoder?
    private var running = false
    private let log = Logger(subsystem: "vn.xox.xdesk", category: "audio-player")

    public init() {}

    public var isMuted: Bool {
        get { state.withLock { $0.muted } }
        set { state.withLock { $0.muted = newValue } }
    }

    public var stats: AudioPlaybackStats {
        state.withLock { s in
            var out = s.stats
            out.jitterDepthMs = s.jitter.depthMs
            out.underruns = s.jitter.counters.underruns
            out.concealedFrames = s.jitter.counters.concealedFrames
            return out
        }
    }

    public func start() throws {
        guard !running else { return }
        try AudioSessionConfigurator.activate()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(AudioPayload.sampleRate), channels: 2) else {
            throw AudioCodecError.unavailable
        }
        let state = self.state
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            Self.render(state: state, frameCount: Int(frameCount), into: audioBufferList)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
        try engine.start()
        running = true
        let latency = Int((engine.outputNode.presentationLatency + AudioSessionConfigurator.outputLatency) * 1000)
        self.state.withLock { $0.stats.outputLatencyMs = latency }
    }

    public func stop() {
        guard running else { return }
        running = false
        engine.stop()
        if let sourceNode { engine.detach(sourceNode) }
        sourceNode = nil
        AudioSessionConfigurator.deactivate()
        state.withLock { $0 = State() }
        decoder = nil
    }

    /// Nhận một gói media ptype 0x20. Gói sai chỉ bị đếm.
    public func ingest(_ packet: MediaPacket) {
        guard packet.header.type == .audio else { return }
        do {
            let payload = try AudioPayload.decode(packet.payload)
            let pcm = try samples(from: payload)
            state.withLock { s in
                s.stats.packets += 1
                s.stats.codec = payload.codec
                s.stats.hostHoldMs = Int(payload.holdMs)
                s.stats.lastPeak = pcm.reduce(0) { max($0, abs(Int($1))) }
                if s.stats.lastPeak > Self.onsetPeak {
                    if s.quietPackets >= Self.onsetQuietPackets {
                        s.stats.onsets += 1
                        s.stats.lastOnsetUnixMs = Int64(Date().timeIntervalSince1970 * 1000)
                    }
                    s.quietPackets = 0
                } else {
                    s.quietPackets += 1
                }
                s.jitter.push(sequence: packet.header.frameNo, pcm: pcm)
            }
        } catch {
            state.withLock { $0.stats.malformed += 1 }
            log.error("audio packet dropped: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func samples(from payload: AudioPayload) throws -> [Int16] {
        switch payload.codec {
        case .pcm: return AudioPacketizer.samples(fromLittleEndian: payload.data)
        case .aacEld:
            if decoder == nil { decoder = try AacEldDecoder() }
            guard let decoder else { throw AudioCodecError.unavailable }
            return try decoder.decode(payload.data)
        }
    }

    private static func render(state: OSAllocatedUnfairLock<State>, frameCount: Int, into list: UnsafeMutablePointer<AudioBufferList>) {
        let (pcm, muted) = state.withLock { ($0.jitter.pull(frames: frameCount), $0.muted) }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard buffers.count >= 2,
              let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
              let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return }
        if muted {
            for i in 0..<frameCount {
                left[i] = 0
                right[i] = 0
            }
            return
        }
        let scale = 1 / Float(Int16.max)
        for i in 0..<frameCount {
            left[i] = Float(pcm[2 * i]) * scale
            right[i] = Float(pcm[2 * i + 1]) * scale
        }
    }
}
