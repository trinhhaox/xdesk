import Foundation
import XdeskMedia
import XdeskTransport
import XdeskWire

extension ViewerSession {
    // MARK: Điều khiển

    func readControl(_ conn: ControlConnection) async {
        do {
            while let inbound = try await conn.nextInbound() {
                if case .bulk(let chunk) = inbound {
                    if await fileReceiver.handleBulk(chunk) { continue }
                    await clipboardSync?.handleBulk(chunk)
                    continue
                }
                if case .mediaOverTcp(let packet) = inbound { await channel?.ingest(packet); continue }
                guard case .message(let envelope) = inbound else { continue }
                switch envelope.message {
                case .clipOffer, .clipPull, .clipData: await clipboardSync?.handle(envelope.message)
                case .fileStart(let start): await fileReceiver.handleStart(start)
                case .fileChunk(let header): await fileReceiver.handleChunkHeader(header)
                case .fileDone(let done): await fileReceiver.handleDone(done)
                case .fileCancel(let cancel):
                    if cancel.reason == FileTransferDenial.reason { lastFileTransferError = FileTransferDenial.message }
                    if activeSendingFileId == cancel.id {
                        fileCancelToken.cancel(cancel.id)
                    } else {
                        await fileReceiver.handleCancel(cancel)
                    }
                case .displayList(let list): hostDisplays = list.displays
                case .systemUnlockResult(let result): lastUnlockResult = result
                case .systemLockResult(let result): lastLockResult = result
                case .hostState(let state):
                    let recovered = hostVideoUnavailable && state.videoAvailable
                    hostState = state
                    if recovered { await requestKeyframe() }
                case .systemUnlockChallenge(let challenge): Task { [weak self] in await self?.answerUnlockChallenge(challenge) }
                case .windowSelected(let selected):
                    selectedWindow = selected
                    onWindowSelected?(selected)
                case .displayReady: finishReconfigure(id: envelope.id, ok: true)
                case .pong(let pong): updateClock(ClockSample(pong: pong, receivedAtMs: ClockSync.wallClockMs()))
                case .bye(let bye): throw TransportError.rejected(reason: "bye", detail: bye.reason)
                case .reject(let reject) where reject.reason == Reject.reasonRevoked:
                    await forgetRevokedHost()
                    throw TransportError.revokedByHost
                case .rekeyResync(let resync): await channel?.handleResync(resync)
                case .agentApprove(let approve) where approve.isRequest: receiveAgentApproval(approve)
                case .agentHelp(let help) where !help.isResolved:
                    pendingAgentHelp = AgentHelpNotice(requestId: help.requestId, reason: help.reason ?? "Cần người dùng hỗ trợ")
                default: break
                }
            }
            await fail(String(localized: "Host đã ngắt kết nối", bundle: .module), transient: true)
        } catch {
            await fail(error.localizedDescription, transient: Self.isTransientError(error))
        }
    }

    func pingLoop(_ conn: ControlConnection) async {
        var interval = 100
        while !Task.isCancelled {
            do { _ = try await conn.send(.ping(Ping(t0: ClockSync.wallClockMs()))) } catch { return }
            try? await Task.sleep(for: .milliseconds(interval))
            interval = min(1000, interval + 100)
        }
    }

    // MARK: Video

    func consume(_ events: AsyncStream<UdpMediaChannel.Event>) async {
        for await event in events {
            switch event {
            case .frame(let frame): render(frame)
            case .keyframeNeeded: await requestKeyframe()
            case .packet(let packet):
                handleInputAck(packet)
                handleAudio(packet)
            case .peerConnected: break
            case .linkLost: await fail(String(localized: "Mất liên lạc với host (UDP)", bundle: .module), transient: true)
            }
        }
    }

    private func render(_ frame: AssembledFrame) {
        stats.record(frameNo: frame.frameNo, byteCount: frame.data.count)
        do {
            if let sample = try factory.makeSampleBuffer(annexB: frame.data, ptsMs: frame.ptsMs, isKeyframe: frame.isKeyframe) {
                if !renderer.enqueue(sample) { Task { await requestKeyframe() } }
            } else if !frame.isKeyframe {
                Task { await requestKeyframe() }
            }
        } catch {
            log.error("decode failed: \(error.localizedDescription, privacy: .public)")
            Task { await requestKeyframe() }
        }
    }

    private func requestKeyframe() async {
        let now = Int(ProcessInfo.processInfo.systemUptime * 1000)
        guard now - lastKeyframeRequestMs >= Self.keyframeRequestMinGapMs, let connection else { return }
        lastKeyframeRequestMs = now
        do { _ = try await connection.send(.keyframeRequest(KeyframeRequest(streamId: streamId))) } catch {
            log.error("keyframe.request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func reportLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            await reportNow()
        }
    }

    private func reportNow() async {
        let now = Int(ProcessInfo.processInfo.systemUptime * 1000)
        guard let window = stats.closeWindow(nowMs: now), let connection else { return }
        updateRates(fps: window.fps, recvKbps: window.recvKbps)
        refreshAudioStats()
        #if DEBUG
        windowCount += 1
        if windowCount % 4 == 0 {
            log.notice("stats fps=\(window.fps) kbps=\(window.recvKbps) lossPermille=\(window.lossPermille) rttMs=\(self.rttMs ?? -1) offsetMs=\(self.clockOffsetMs ?? .nan)")
        }
        #endif
        let report = NetReport(
            rttMs: UInt32(max(0, rttMs ?? 0)), lossPermille: UInt32(min(1000, window.lossPermille)), jitterMs: 0,
            recvKbps: UInt32(window.recvKbps)
        )
        do { _ = try await connection.send(.netReport(report)) } catch {
            log.error("net.report failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
