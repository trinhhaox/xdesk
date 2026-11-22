import CoreGraphics
import CoreMedia
import Foundation
import os
import XdeskMedia

/// Capture → encode cho một phiên. Khung chỉ được mã hoá khi viewer đã báo địa chỉ UDP (`beginStreaming`);
/// giữ khung mới nhất để mã hoá lại thành keyframe khi viewer tới/xin keyframe lúc màn hình đang tĩnh (SCK không phát khung).
final class HostPipeline: @unchecked Sendable {
    let encoder: VideoEncoder
    private let displayID: CGDirectDisplayID
    private let settings: EncoderSettings
    private let onStop: @Sendable (Error?) -> Void
    private let audioSink: (@Sendable (_ samples: [Int16], _ captureMs: Double, _ nowMs: Double) -> Void)?
    private let log = Logger(subsystem: "vn.xox.xdesk", category: "host-pipeline")
    private let lock = NSLock()
    private let origin: Double
    private var capture: CaptureService?
    private var latest: CapturedFrame?
    private var streaming = false
    private var videoPaused: Bool
    private var stopped = false
    private var lastPtsMs: UInt32 = 0
    private lazy var idleRepeater = IdleFrameRepeater { [weak self] in self?.repeatLatest() }

    /// `audioSink` có thì capture cả âm thanh: mẫu s16 xen kẽ, mốc ghi và giờ hiện tại đều theo đồng hồ video (ms từ lúc mở pipeline).
    init(
        displayID: CGDirectDisplayID, settings: EncoderSettings,
        origin: Double = ProcessInfo.processInfo.systemUptime,
        initiallyPaused: Bool = false,
        audioSink: (@Sendable ([Int16], Double, Double) -> Void)? = nil,
        onStop: @escaping @Sendable (Error?) -> Void
    ) throws {
        self.origin = origin
        self.videoPaused = initiallyPaused
        self.audioSink = audioSink
        self.displayID = displayID
        self.settings = settings
        self.onStop = onStop
        encoder = try VideoEncoder(settings: settings)
    }

    func start() async throws {
        let shouldStartCapture = lock.withLock { !stopped && (!videoPaused || audioSink != nil) }
        guard shouldStartCapture else { return }
        try await startCaptureOnly()
    }

    private func startCaptureOnly() async throws {
        var audioHandler: (@Sendable (CMSampleBuffer) -> Void)?
        if audioSink != nil { audioHandler = { [self] sample in self.handleAudio(sample) } }
        let service = CaptureService(
            displayID: displayID, width: settings.width, height: settings.height, fps: settings.fps,
            onFrame: { [self] frame in handle(frame) }, onStop: onStop,
            onAudio: audioHandler
        )
        try await service.start()
        let cancelled = lock.withLock { () -> Bool in
            if stopped { return true }
            capture = service
            return false
        }
        if cancelled { await service.stop() }
    }

    private func stopCaptureOnly() async {
        let service = lock.withLock { () -> CaptureService? in
            idleRepeater.cancel()
            defer { capture = nil; latest = nil }
            return capture
        }
        await service?.stop()
    }

    /// Tạm dừng hoặc bật lại capture/encode video (vd. chuyển sang Chuột/Bàn phím). Nếu không truyền âm thanh sẽ tắt SCStream hẳn.
    func setVideoPaused(_ paused: Bool) async {
        let changed = lock.withLock { () -> Bool in
            guard !stopped, videoPaused != paused else { return false }
            videoPaused = paused
            if paused { idleRepeater.cancel() }
            return true
        }
        guard changed else { return }
        if paused {
            if audioSink == nil { await stopCaptureOnly() }
            return
        }
        let needsCapture = lock.withLock { !stopped && capture == nil }
        if needsCapture {
            do {
                try await startCaptureOnly()
            } catch {
                log.error("resume capture failed: \(error.localizedDescription, privacy: .public)")
                onStop(error)
                return
            }
        }
        let canKeyframe = lock.withLock { !stopped && streaming && !videoPaused }
        if canKeyframe { requestKeyframe() }
    }

    /// Viewer đã sẵn sàng nhận: bắt đầu mã hoá và phát keyframe ngay từ khung mới nhất.
    func beginStreaming() {
        let shouldKeyframe = lock.withLock { () -> Bool in
            streaming = true
            return !videoPaused
        }
        if shouldKeyframe { requestKeyframe() }
    }

    func requestKeyframe() {
        encoder.requestKeyframe()
        guard let frame = lock.withLock({ (streaming && !videoPaused) ? latest : nil }) else { return }
        encode(frame)
    }

    func stop() async {
        let service = lock.withLock { () -> CaptureService? in
            stopped = true
            streaming = false
            idleRepeater.cancel()
            defer { capture = nil; latest = nil }
            return capture
        }
        await service?.stop()
        encoder.invalidate()
    }

    private func handle(_ frame: CapturedFrame) {
        let active = lock.withLock { () -> Bool in
            latest = frame
            return streaming && !videoPaused && !stopped
        }
        if active { encode(frame) }
    }

    /// Màn hình đứng yên: mã hoá lại khung cuối một lần để đẩy khung đang kẹt trong decoder phần cứng của viewer.
    private func repeatLatest() {
        guard let frame = lock.withLock({ (streaming && !videoPaused && !stopped) ? latest : nil }) else { return }
        encode(frame, flushable: false)
    }

    private func handleAudio(_ sample: CMSampleBuffer) {
        guard let audioSink, let pcm = AudioCaptureTap.convert(sample) else { return }
        let nowMs = (ProcessInfo.processInfo.systemUptime - origin) * 1000
        audioSink(pcm.samples, nowMs - pcm.ageMs, nowMs)
    }

    private func encode(_ frame: CapturedFrame, flushable: Bool = true) {
        do {
            try encoder.encode(frame.pixelBuffer, ptsMs: nextPtsMs())
            if flushable { idleRepeater.frameEncoded() }
        } catch {
            log.error("encode failed: \(error.localizedDescription, privacy: .public)")
            onStop(error)
        }
    }

    /// Đơn điệu tăng chặt (mã hoá lại cùng khung trong cùng ms vẫn cần PTS mới).
    private func nextPtsMs() -> UInt32 {
        lock.withLock {
            let now = UInt32(truncatingIfNeeded: Int((ProcessInfo.processInfo.systemUptime - origin) * 1000))
            lastPtsMs = max(now, lastPtsMs &+ 1)
            return lastPtsMs
        }
    }
}
