import Foundation
import XdeskTransport
import XdeskWire

extension HostSession {
    // MARK: Vòng điều khiển

    func controlLoop() async throws {
        while let inbound = try await connection.nextInbound() {
            if case .bulk(let chunk) = inbound { await clipboard?.handleBulk(chunk); continue }
            if case .mediaOverTcp(let packet) = inbound { await channel?.ingest(packet); continue }
            guard case .message(let envelope) = inbound else { continue }
            switch envelope.message {
            case .clipOffer, .clipPull, .clipData: await clipboard?.handle(envelope.message)
            case .keyframeRequest: pipeline?.requestKeyframe()
            case .netReport(let r): try await applyNetReport(r)
            case .ping(let ping):
                let t1 = ClockSync.wallClockMs()
                let pong = ClockSync.makePong(for: ping, receivedAtMs: t1, sentAtMs: ClockSync.wallClockMs())
                _ = try await connection.send(.pong(pong), id: envelope.id)
            case .inputText(let t): await handleInputText(t.text)
            case .rekeyResync(let resync): await channel?.handleResync(resync)
            case .agentApprove(let answer) where !answer.isRequest:
                // Chỉ thiết bị có quyền điều khiển mới được duyệt quyền cho agent.
                if permissions.input { onAgentAnswer(answer.requestId, answer.allow ?? false) }
            case .bye: return
            default: break
            }
        }
    }

    func applyNetReport(_ r: NetReport) async throws {
        let now = Int(ProcessInfo.processInfo.systemUptime * 1000)
        guard let kbps = bitrate.update(lossPermille: Int(r.lossPermille), rttMs: Int(r.rttMs), nowMs: now) else { return }
        audio?.update(estimateKbps: kbps)
        try pipeline?.encoder.setBitrate(kbps: kbps)
        _ = try await connection.send(.bitrateSet(BitrateSet(kbps: UInt32(kbps))))
    }
}
