import XdeskWire

/// Gói `probe` (ptype 0x50): viewer gửi định kỳ tới khi nhận gói đầu tiên của host, để host biết địa chỉ UDP viewer.
/// Payload rỗng hoặc u64 nonce; host chỉ chấp nhận từ IP của peer TCP (xem `UdpMediaChannel.adopt`).
enum MediaPunch {
    static func packet(streamId: UInt16, nonce: UInt64? = nil) -> MediaPacket {
        var payload: [UInt8] = []
        if let nonce { payload = (0..<8).map { UInt8(truncatingIfNeeded: nonce >> UInt64(56 - 8 * $0)) } }
        return MediaPacket(header: MediaHeader(type: .probe, streamId: streamId, frameNo: 0), payload: payload)
    }

    static func isProbe(_ p: MediaPacket) -> Bool {
        p.header.type == .probe && (p.payload.isEmpty || p.payload.count == 8)
    }
}
