import CoreGraphics
import Foundation
import XdeskMedia
import XdeskTransport
import XdeskWire

/// Hình + phiên khi Mac ngủ/khoá: capture/màn hình ảo không khởi động được (hoặc đang chạy thì dừng) vì màn hình tắt hay đang khoá
/// thì phiên KHÔNG đóng: kênh điều khiển, UDP keepalive, input, khoá/mở khoá, clipboard vẫn chạy, viewer nhận `host.state`
/// `videoAvailable:false`. Khi Mac thức dậy/mở khoá và capture được thì video chạy lại bằng keyframe và viewer nhận `videoAvailable:true`.
extension HostSession {
    private enum StartOutcome { case started, unavailable }

    // MARK: Khởi động

    /// Khởi động (hoặc khởi động lại, vd. reconfigure) video theo `config`. Lỗi do ngủ/khoá → chuyển sang "không có hình"
    /// thay vì ném lỗi; lỗi khác vẫn ném như trước.
    func startVideoOrDefer(_ config: DisplayConfig) async throws {
        try await withVideoLock {
            guard !ended else { return }
            videoConfig = config
            switch try await attemptVideoStart(config) {
            case .started: await markVideoAvailable()
            case .unavailable: await enterVideoUnavailable()
            }
        }
    }

    private func attemptVideoStart(_ config: DisplayConfig) async throws -> StartOutcome {
        await stopVideoPipeline()
        let state = screenState()
        if !state.displayAwake {
            log.notice("Màn hình Mac đang tắt: giữ phiên, chưa có hình")
            return .unavailable
        }
        do {
            try await startVideo(config)
            return .started
        } catch {
            guard await VideoAvailability.keepsSession(after: error, probe: screenState) else { throw error }
            log.notice("Chưa capture được vì Mac đang khoá/ngủ, giữ phiên: \(error.localizedDescription, privacy: .public)")
            await stopVideoPipeline()
            await provider.release()
            return .unavailable
        }
    }

    private func startVideo(_ config: DisplayConfig) async throws {
        guard let channel else { throw TransportError.noPeer }
        let (acquired, width, height) = try await acquireDisplay(for: config)
        if let reason = acquired.fallbackReason { log.notice("fallback mirror: \(reason, privacy: .public)") }
        log.notice("màn hình \(acquired.mode == .native ? "native" : "ảo", privacy: .public) \(width)x\(height) fit=\(config.fit.rawValue, privacy: .public)")
        if let input { await input.updateDisplay(acquired.displayID) } else { await startInput(displayID: acquired.displayID) }
        await beginWindowFit(config, displayID: acquired.displayID)
        await configureWindowControl(displayID: acquired.displayID, config: config, pixelWidth: width, pixelHeight: height)

        let paused = config.videoPaused ?? false
        videoPaused = paused
        if audio == nil { audio = await makeAudioStreamer(caps: negotiatedCaps, channel: channel) }
        let audioSink = audio.map { streamer in { @Sendable (samples: [Int16], captureMs: Double, nowMs: Double) in streamer.ingest(samples: samples, captureMs: captureMs, nowMs: nowMs) } }
        videoGeneration += 1
        let generation = videoGeneration
        let settings = EncoderSettings(width: width, height: height, fps: Int(config.fps), bitrateKbps: bitrate.kbps, codec: config.codec)
        let next = try HostPipeline(
            displayID: acquired.displayID, settings: settings, origin: pipelineOrigin,
            initiallyPaused: paused, audioSink: audioSink
        ) { [weak self] error in
            Task { await self?.pipelineStopped(error, generation: generation) }
        }
        pipeline = next
        try await next.start()
        let counter = frameCounter
        framePumpTask = Task { await Self.pumpFrames(next.encoder, counter: counter, to: channel) }
        videoShape = VideoShape(mode: acquired.mode, width: width, height: height)
        if viewerReady && !paused { next.beginStreaming() }
    }

    /// Dừng capture/encode và trả cửa sổ đã co; không đụng màn hình ảo (do `acquire` sau đó thay thế hoặc `enterVideoUnavailable` trả).
    func stopVideoPipeline() async {
        videoGeneration += 1
        framePumpTask?.cancel()
        framePumpTask = nil
        await pipeline?.stop()
        pipeline = nil
        await endWindowFit()
    }

    // MARK: Chuyển trạng thái

    private func enterVideoUnavailable() async {
        videoUnavailable = true
        await input?.updateDisplay(CGMainDisplayID())
        await publishHostState()
        startVideoRetryWatch()
    }

    private func markVideoAvailable() async {
        videoUnavailable = false
        videoRetryTask?.cancel()
        videoRetryTask = nil
        await publishHostState()
    }

    /// SCStream dừng/encode lỗi giữa chừng: Mac ngủ/khoá → chuyển sang không có hình; lỗi khác → báo `bye` và đóng như cũ.
    func pipelineStopped(_ error: Error?, generation: Int) async {
        await withVideoLock {
            guard !ended, generation == videoGeneration, pipeline != nil else { return }
            let keep = await VideoAvailability.keepsSession(after: error, probe: screenState, grace: .milliseconds(1500))
            guard keep else {
                _ = try? await connection.send(.bye(Bye(reason: error?.localizedDescription ?? "capture stopped")))
                await connection.close()
                return
            }
            log.notice("Capture dừng vì Mac ngủ/khoá, giữ phiên")
            await stopVideoPipeline()
            await provider.release()
            await enterVideoUnavailable()
        }
    }

    // MARK: Thử lại

    private func startVideoRetryWatch() {
        videoRetryTask?.cancel()
        let signals = screenWakeEvents()
        let poll = videoRetryPoll
        // Giữ `self` mạnh: vòng thử lại kết thúc khi video chạy lại hoặc `teardown` huỷ task.
        videoRetryTask = Task { [self] in
            await VideoRetryLoop.run(signals: signals, poll: poll) { trigger in await self.retryVideo(trigger) }
        }
    }

    /// `true` = xong (video chạy lại, phiên đã kết thúc hoặc không còn cần thử).
    func retryVideo(_ trigger: VideoRetryPolicy.Trigger) async -> Bool {
        await withVideoLock {
            guard !ended, videoUnavailable, let config = videoConfig else { return true }
            guard VideoRetryPolicy.shouldRetry(trigger, state: screenState()) else {
                await publishHostState()
                return false
            }
            do {
                guard try await attemptVideoStart(config) == .started else {
                    await publishHostState()
                    return false
                }
            } catch {
                // Màn hình vừa sáng ở màn khoá thì capture vẫn có thể lỗi: giữ phiên, chờ tín hiệu tiếp theo.
                if await VideoAvailability.keepsSession(after: error, probe: screenState, grace: .milliseconds(1500)) {
                    log.notice("Chưa capture lại được vì Mac còn khoá/ngủ, giữ phiên: \(error.localizedDescription, privacy: .public)")
                    await stopVideoPipeline()
                    await provider.release()
                    await publishHostState()
                    return false
                }
                log.error("khởi động lại video lỗi: \(error.localizedDescription, privacy: .public)")
                _ = try? await connection.send(.bye(Bye(reason: error.localizedDescription)))
                await connection.close()
                return true
            }
            await markVideoAvailable()
            log.notice("Video chạy lại sau khi Mac thức/mở khoá")
            await reportCurrentStreaming(config)
            await sendDisplayListIfSupported()
            return true
        }
    }

    // MARK: host.state

    /// Gửi `host.state` khi nội dung đổi (trạng thái đầu tiên "có hình" không cần gửi: viewer coi mặc định là có hình).
    func publishHostState() async {
        let next = HostState(videoAvailable: !videoUnavailable, locked: screenState().locked)
        guard next != lastHostState, lastHostState != nil || !next.videoAvailable else { return }
        lastHostState = next
        do { _ = try await connection.send(.hostState(next)) } catch {
            log.error("gửi host.state lỗi: \(error.localizedDescription, privacy: .public)")
        }
    }

    func reportCurrentStreaming(_ config: DisplayConfig) async {
        let shape = videoShape ?? VideoShape(mode: config.isNativeMirror ? .native : .mirror, width: Int(config.w), height: Int(config.h))
        await reportStreaming(mode: shape.mode, width: shape.width, height: shape.height, config: config)
    }

    func sendDisplayListIfSupported() async {
        guard negotiatedCaps.contains(.multiDisplay) else { return }
        let displays = await physicalDisplays()
        if !displays.isEmpty { _ = try? await connection.send(.displayList(DisplayList(displays: displays))) }
    }

    // MARK: Khoá tuần tự

    /// Các thao tác khởi động/dừng/chuyển trạng thái video không được chạy chồng nhau (actor tái nhập ở mỗi `await`).
    func withVideoLock<T>(_ body: () async throws -> T) async rethrows -> T {
        if videoBusy { await withCheckedContinuation { videoWaiters.append($0) } }
        videoBusy = true
        defer {
            if videoWaiters.isEmpty { videoBusy = false } else { videoWaiters.removeFirst().resume() }
        }
        return try await body()
    }
}

struct VideoShape: Sendable, Equatable {
    var mode: DisplayMode
    var width: Int
    var height: Int
}
