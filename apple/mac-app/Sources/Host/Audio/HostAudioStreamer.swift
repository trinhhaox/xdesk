import Foundation
import os
import XdeskMedia
import XdeskTransport
import XdeskWire

/// Âm thanh Mac → viewer cho một phiên: gom mẫu từ SCK → gói PCM/AAC-ELD → kênh media (UDP hoặc MediaOverTcp).
/// Quyền `audio` của thiết bị được kiểm lại mỗi giây (tắt giữa phiên → ngừng gửi ngay); chỉ gửi sau khi viewer đã báo địa chỉ.
final class HostAudioStreamer: @unchecked Sendable {
    struct Snapshot: Sendable, Equatable {
        var packetsSent = 0
        var codec: AudioWireCodec
    }

    private struct State {
        var packetizer: AudioPacketizer
        var policy: AudioCodecPolicy
        var active = false
        var allowed = true
        var sent = 0
        var failures = 0
    }

    private let state: OSAllocatedUnfairLock<State>
    private let outbox: AsyncStream<MediaPacket>.Continuation
    private var tasks: [Task<Void, Never>] = []
    private let log = Logger(subsystem: "vn.xox.xdesk", category: "host-audio")

    /// `nil` khi hai bên không có codec audio chung. `narrowPath`: Tailscale/USB → AAC-ELD.
    init?(
        negotiated: Capabilities, narrowPath: Bool, streamId: UInt16, channel: UdpMediaChannel,
        isAllowed: @escaping @Sendable () async -> Bool
    ) {
        guard let policy = AudioCodecPolicy(negotiated: negotiated, narrowPath: narrowPath) else { return nil }
        state = OSAllocatedUnfairLock(uncheckedState: State(packetizer: AudioPacketizer(streamId: streamId), policy: policy))
        let (packets, continuation) = AsyncStream.makeStream(of: MediaPacket.self, bufferingPolicy: .bufferingNewest(256))
        outbox = continuation
        let log = self.log
        tasks.append(Task { [weak self] in
            for await packet in packets {
                do { try await channel.sendPacket(packet) } catch { self?.recordFailure(error, log: log) }
            }
        })
        let state = self.state
        tasks.append(Task {
            while !Task.isCancelled {
                let allowed = await isAllowed()
                state.withLock { $0.allowed = allowed }
                try? await Task.sleep(for: .seconds(1))
            }
        })
    }

    /// Viewer đã sẵn sàng nhận (đã báo địa chỉ UDP / đã vào đường hầm).
    func setActive(_ active: Bool) { state.withLock { $0.active = active } }

    /// Ước lượng băng thông (kb/s) = bitrate video mà ABR cho phép; có thể đổi codec giữa phiên.
    func update(estimateKbps: Int) { _ = state.withLock { $0.policy.update(estimateKbps: estimateKbps) } }

    var snapshot: Snapshot { state.withLock { Snapshot(packetsSent: $0.sent, codec: $0.policy.codec) } }

    /// Gọi từ hàng đợi audio của SCK.
    func ingest(samples: [Int16], captureMs: Double, nowMs: Double) {
        #if DEBUG
        traceOnset(samples, captureMs: captureMs, nowMs: nowMs)
        #endif
        let packets: [MediaPacket] = state.withLock { s in
            guard s.active, s.allowed else { return [] }
            do {
                let out = try s.packetizer.push(samples: samples, captureMs: captureMs, nowMs: nowMs, codec: s.policy.codec)
                s.sent += out.count
                return out
            } catch {
                s.failures += 1
                return []
            }
        }
        for packet in packets { outbox.yield(packet) }
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        outbox.finish()
    }

    private func recordFailure(_ error: any Error, log: Logger) {
        let count = state.withLock { s -> Int in
            s.failures += 1
            return s.failures
        }
        if count == 1 || count % 500 == 0 { log.error("audio send failed (\(count)): \(error.localizedDescription, privacy: .public)") }
    }

    #if DEBUG
    private let traceQuiet = OSAllocatedUnfairLock(initialState: true)

    /// Kiểm thử độ trễ (env XDESK_AUDIO_TRACE=1): in giờ máy lúc SCK giao đoạn có tiếng đầu tiên sau im lặng.
    private func traceOnset(_ samples: [Int16], captureMs: Double, nowMs: Double) {
        guard ProcessInfo.processInfo.environment["XDESK_AUDIO_TRACE"] != nil else { return }
        let peak = samples.reduce(0) { max($0, abs(Int($1))) }
        let loud = peak > 3_000
        let fire = traceQuiet.withLock { quiet -> Bool in
            defer { quiet = !loud }
            return quiet && loud
        }
        if fire {
            print("xdesk-host-audio-onset wallMs=\(Int64(Date().timeIntervalSince1970 * 1000)) peak=\(peak) bufferAgeMs=\(Int(nowMs - captureMs)) frames=\(samples.count / 2)")
            fflush(stdout)
        }
    }
    #endif
}
