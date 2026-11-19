import CryptoKit
import XdeskCrypto
import XdeskWire

/// Cặp cipher TCP của một kết nối (mỗi hướng một khoá, nonce đếm frame). Chỉ `ControlConnection` sở hữu; không copy được.
struct ControlCipher: ~Copyable, Sendable {
    static let rekeyInterval: Duration = .seconds(3600)
    static let rekeyFrameThreshold: UInt64 = 1 << 32

    private var sender: StreamSender
    private var receiver: StreamReceiver
    private var framesSinceRekey: UInt64 = 0
    private var sendEpochStart: ContinuousClock.Instant

    init(keys: SessionKeys, now: ContinuousClock.Instant = .now) {
        sender = StreamSender(key: keys.tcpSend)
        receiver = StreamReceiver(key: keys.tcpReceive)
        sendEpochStart = now
    }

    func needsSendRekey(interval: Duration, now: ContinuousClock.Instant = .now) -> Bool {
        framesSinceRekey >= Self.rekeyFrameThreshold || now - sendEpochStart >= interval
    }

    /// Frame → byte trên dây: `len | kind | ciphertext | tag`.
    mutating func seal(_ frame: ControlFrame) throws -> [UInt8] {
        if frame.kind == .bulk, frame.payload.count > ControlFrame.maxBulkPayload { throw WireError.payloadTooLarge(frame.payload.count) }
        let ciphertext = try sender.seal(kind: frame.kind.rawValue, plaintext: frame.payload)
        framesSinceRekey += 1
        let len = UInt32(1 + ciphertext.count)
        return [UInt8(len >> 24), UInt8((len >> 16) & 0xFF), UInt8((len >> 8) & 0xFF), UInt8(len & 0xFF), frame.kind.rawValue] + ciphertext
    }

    mutating func open(_ frame: ControlFrame) throws -> ControlFrame {
        ControlFrame(kind: frame.kind, payload: try receiver.open(kind: frame.kind.rawValue, ciphertext: frame.payload))
    }

    mutating func rekeySend(now: ContinuousClock.Instant = .now) {
        sender.rekey()
        framesSinceRekey = 0
        sendEpochStart = now
    }

    mutating func rekeyReceive() { receiver.rekey() }
}
