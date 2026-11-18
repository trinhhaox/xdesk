import Foundation
import XdeskInput
import XdeskTransport
import XdeskWire

extension ViewerSession {
    static let inputMaintenanceIntervalMs = 50
    static let heartbeatIntervalMs: Int64 = 250

    /// Gửi sự kiện input tới host qua UDP. Gọi từ main actor; bỏ qua khi chưa `.streaming`.
    /// down/up/key được cấp seq và gửi lại tới khi host ack; move/scroll gửi một lần.
    /// Khi còn nút/phím đang giữ, phiên tự gửi heartbeat để host không nhả nhầm.
    public func sendInput(_ events: [InputEvent]) {
        guard state == .streaming else { return }
        let valid = events.compactMap { $0.sanitized() }
        guard !valid.isEmpty else { return }
        enqueueInput(inputSequencer.prepare(valid, nowMs: Self.uptimeMs))
    }

    /// Gửi chuỗi Unicode đã gõ xong (bàn phím ảo/IME) qua control `input.text`; chuỗi dài được chia ≤ 4096 byte.
    /// Trả về false nếu chưa kết nối hoặc gửi lỗi.
    @discardableResult
    public func sendText(_ text: String) async -> Bool {
        guard state == .streaming, let connection, !text.isEmpty else { return false }
        for chunk in TextChunker.splitUtf8(text, maxBytes: InputText.maxBytes) {
            do { _ = try await connection.send(.inputText(InputText(text: chunk))) } catch {
                log.error("input.text failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        return true
    }

    func pumpInput(_ packets: AsyncStream<MediaPacket>, to channel: UdpMediaChannel) async {
        for await packet in packets {
            do { try await channel.sendPacket(packet) } catch {
                log.error("input send failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func inputMaintenanceLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(Self.inputMaintenanceIntervalMs))
            let now = Self.uptimeMs
            let due = inputSequencer.resendDue(nowMs: now)
            if !due.abandoned.isEmpty { log.error("input abandoned without ack: \(due.abandoned.count)") }
            var outgoing = due.resend
            if inputSequencer.hasHeldInput, now - lastHeartbeatMs >= Self.heartbeatIntervalMs { outgoing.append(.heartbeat) }
            if !outgoing.isEmpty {
                if outgoing.contains(.heartbeat) { lastHeartbeatMs = now }
                enqueueInput(outgoing)
            }
        }
    }

    func handleInputAck(_ packet: MediaPacket) {
        guard packet.header.type == .inputAck else { return }
        guard let ack = try? InputAck.decode(packet.payload) else {
            log.error("malformed input-ack")
            return
        }
        inputSequencer.acknowledge(upTo: ack.seq)
    }

    private func enqueueInput(_ events: [InputEvent]) {
        for batch in InputSequencer.batches(events) {
            do { inputOutbox?.yield(try MediaPacket.input(streamId: streamId, events: batch)) } catch {
                log.error("input encode failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static var uptimeMs: Int64 { Int64(ProcessInfo.processInfo.systemUptime * 1000) }
}
