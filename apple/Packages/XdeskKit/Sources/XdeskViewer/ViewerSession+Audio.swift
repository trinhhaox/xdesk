import XdeskMedia
import XdeskWire

/// Cấu hình audio của app viewer: có thì viewer xin audio (host chỉ cấp nếu thiết bị này có quyền `audio`).
public struct AudioConfig: Sendable {
    public init() {}
}

extension ViewerSession {
    /// Bật trình phát khi host đã thương lượng audio. Lỗi (không có thiết bị ra, phiên audio bị chiếm) chỉ tắt tiếng, không làm hỏng phiên video.
    func startAudio(negotiated: Capabilities) {
        guard audioConfig != nil, negotiated.contains(.audioPCM) || negotiated.contains(.audioAACELD) else { return }
        let player = AudioPlayer()
        do {
            try player.start()
            audioPlayer = player
            audioStats = player.stats
        } catch {
            log.error("không bật được audio: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        audioStats = nil
    }

    func handleAudio(_ packet: MediaPacket) { audioPlayer?.ingest(packet) }

    func refreshAudioStats() { if let audioPlayer { audioStats = audioPlayer.stats } }
}
