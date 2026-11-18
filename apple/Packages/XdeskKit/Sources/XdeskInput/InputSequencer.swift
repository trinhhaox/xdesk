import XdeskWire

/// Phía gửi của kênh input: cấp seq cho sự kiện cần tin cậy (down/up/key), giữ tới khi nhận input-ack,
/// gửi lại mỗi `resendIntervalMs` tối đa `maxResends` lần rồi bỏ. Thời gian do người gọi truyền vào để test xác định.
public struct InputSequencer: Sendable {
    public static let resendIntervalMs: Int64 = 100
    public static let maxResends = 3

    private struct Pending {
        var event: InputEvent
        var lastSentMs: Int64
        var resends = 0
    }

    private var nextSeq: UInt32 = 1
    private var pending: [Pending] = []
    private var heldButtons: Set<UInt8> = []
    private var heldKeys: Set<UInt16> = []

    public init() {}

    public var pendingCount: Int { pending.count }

    /// Còn nút/phím đang giữ → người gọi nên gửi `InputEvent.heartbeat` định kỳ.
    public var hasHeldInput: Bool { !heldButtons.isEmpty || !heldKeys.isEmpty }

    /// Gán seq cho sự kiện cần tin cậy (seq đơn điệu từ 1; 0 = không tin cậy) và nhớ chúng để gửi lại.
    public mutating func prepare(_ events: [InputEvent], nowMs: Int64) -> [InputEvent] {
        events.map { original in
            guard original.isReliable else { return original }
            var event = original
            event.seq = nextSeq
            nextSeq &+= 1
            track(event)
            pending.append(Pending(event: event, lastSentMs: nowMs))
            return event
        }
    }

    /// Phía nhận đã nhận liên tục tới `seq`.
    public mutating func acknowledge(upTo seq: UInt32) {
        pending.removeAll { $0.event.seq <= seq }
    }

    /// Sự kiện tới hạn gửi lại, và sự kiện bị bỏ vì đã gửi lại đủ `maxResends` lần mà vẫn chưa có ack.
    public mutating func resendDue(nowMs: Int64) -> (resend: [InputEvent], abandoned: [InputEvent]) {
        var resend: [InputEvent] = [], abandoned: [InputEvent] = []
        var kept: [Pending] = []
        for var item in pending {
            guard nowMs - item.lastSentMs >= Self.resendIntervalMs else { kept.append(item); continue }
            if item.resends >= Self.maxResends {
                abandoned.append(item.event)
            } else {
                item.resends += 1
                item.lastSentMs = nowMs
                resend.append(item.event)
                kept.append(item)
            }
        }
        pending = kept
        return (resend, abandoned)
    }

    /// Chia thành các lô ≤ `InputEvent.maxBatch` sự kiện, giữ nguyên thứ tự.
    public static func batches(_ events: [InputEvent]) -> [[InputEvent]] {
        stride(from: 0, to: events.count, by: InputEvent.maxBatch).map {
            Array(events[$0..<min($0 + InputEvent.maxBatch, events.count)])
        }
    }

    private mutating func track(_ event: InputEvent) {
        switch (event.kind, event.button) {
        case (.down, let button): heldButtons.insert(button)
        case (.up, let button): heldButtons.remove(button)
        case (.key, 1): heldKeys.insert(event.keyUsage)
        case (.key, _): heldKeys.remove(event.keyUsage)
        default: break
        }
    }
}
