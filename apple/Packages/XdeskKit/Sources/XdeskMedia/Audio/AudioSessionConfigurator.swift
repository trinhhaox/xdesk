import AVFoundation

/// iOS cần phiên audio đúng loại; macOS không có `AVAudioSession` nên các hàm là no-op.
enum AudioSessionConfigurator {
    #if os(iOS)
    /// `.playback`: vẫn phát khi gạt công tắc im lặng, không trộn micro. IO buffer 5 ms để giữ trễ thấp.
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
    }

    static func deactivate() {
        do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) } catch {
            // Phiên đang bận (vd. có ngắt quãng): hệ thống tự thu hồi khi app không còn phát.
        }
    }

    static var outputLatency: TimeInterval { AVAudioSession.sharedInstance().outputLatency }
    #else
    static func activate() throws {}
    static func deactivate() {}
    static var outputLatency: TimeInterval { 0 }
    #endif
}
