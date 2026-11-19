import Foundation
import Network
import XdeskCrypto
import XdeskWire

extension ControlConnection {
    // MARK: Gửi

    /// Seal (nếu đã mã hoá) và chèn `rekey` khi tới hạn, đồng bộ để thứ tự nonce = thứ tự byte trên dây.
    func wireBytes(for frame: ControlFrame) throws -> [UInt8] {
        switch mode {
        case .plaintext:
            return try ControlFrameCodec.encode(frame)
        case .awaitingKeys:
            guard frame.kind == .handshake else { throw TransportError.protocolViolation("chưa xác thực") }
            return try ControlFrameCodec.encode(frame)
        case .secured:
            guard frame.kind != .handshake else { throw TransportError.protocolViolation("frame bắt tay sau khi đã mã hoá") }
            var out: [UInt8] = []
            if cipher?.needsSendRekey(interval: rekeyInterval) == true {
                let rekey = try ControlMessageCodec.encode(ControlEnvelope(id: 0, message: .rekey))
                out += try sealed(ControlFrame(kind: .control, payload: rekey))
                cipher?.rekeySend()
            }
            return out + (try sealed(frame))
        }
    }

    private func sealed(_ frame: ControlFrame) throws -> [UInt8] {
        guard let bytes = try cipher?.seal(frame) else { throw TransportError.encryptionUnavailable }
        return bytes
    }

    func write(_ bytes: [UInt8]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            connection.send(content: Data(bytes), completion: .contentProcessed { error in
                if let error { cont.resume(throwing: TransportError.connectionFailed("\(error)")) } else { cont.resume() }
            })
        }
    }

    // MARK: Nhận

    /// Chờ thứ kế tiếp; `nil` khi đối tác đóng sạch. Message `t` lạ được bỏ qua (tương thích tiến); `rekey` được xử lý nội bộ.
    public func nextInbound() async throws -> ControlInbound? {
        while true {
            let frame: ControlFrame?
            do {
                frame = try await nextRawFrame()
            } catch {
                close()
                throw error
            }
            guard let raw = frame else { close(); return nil }
            do {
                let frame = try open(raw)
                if mode == .secured, !firstFrameHooks.isEmpty {
                    let hooks = firstFrameHooks
                    firstFrameHooks = []
                    for hook in hooks { await hook() }
                }
                switch frame.kind {
                case .control:
                    let envelope = try ControlMessageCodec.decode(frame.payload)
                    if case .unknown = envelope.message { continue }
                    if case .rekey = envelope.message {
                        cipher?.rekeyReceive()
                        continue
                    }
                    return .message(envelope)
                case .mediaOverTcp: return .mediaOverTcp(try MediaPacket.decode(frame.payload))
                case .bulk: return .bulk(frame.payload)
                case .handshake: return .handshake(frame.payload)
                }
            } catch {
                close()
                throw error
            }
        }
    }

    private func open(_ frame: ControlFrame) throws -> ControlFrame {
        switch mode {
        case .plaintext:
            return frame
        case .awaitingKeys:
            guard frame.kind == .handshake else { throw TransportError.protocolViolation("frame \(frame.kind) trước khi bắt tay xong") }
            return frame
        case .secured:
            guard frame.kind != .handshake else { throw TransportError.protocolViolation("frame bắt tay sau khi đã mã hoá") }
            guard let plain = try cipher?.open(frame) else { throw TransportError.encryptionUnavailable }
            return plain
        }
    }

    func nextRawFrame() async throws -> ControlFrame? {
        while true {
            if let frame = try decoder.next() { return frame }
            guard let chunk = try await readChunk() else { return nil }
            decoder.append(chunk)
        }
    }

    private func readChunk() async throws -> [UInt8]? {
        while true {
            let chunk: [UInt8]? = try await withCheckedThrowingContinuation { cont in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                    if let error {
                        cont.resume(throwing: TransportError.connectionFailed("\(error)"))
                    } else if let data, !data.isEmpty {
                        cont.resume(returning: [UInt8](data))
                    } else if isComplete {
                        cont.resume(returning: nil)
                    } else {
                        cont.resume(returning: [])
                    }
                }
            }
            if chunk?.isEmpty != true { return chunk }
        }
    }
}
