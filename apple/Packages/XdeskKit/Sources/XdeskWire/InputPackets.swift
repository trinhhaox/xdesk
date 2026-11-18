extension MediaPacket {
    /// Gói `input` (ptype 0x30): 1…`InputEvent.maxBatch` sự kiện. Không phân mảnh nên `frameNo` = 0.
    public static func input(streamId: UInt16, events: [InputEvent]) throws -> MediaPacket {
        MediaPacket(header: MediaHeader(type: .input, streamId: streamId, frameNo: 0), payload: try InputEvent.encodeBatch(events))
    }

    /// Gói `input-ack` (ptype 0x31) mang seq liên tục lớn nhất.
    public static func inputAck(streamId: UInt16, ack: InputAck) -> MediaPacket {
        MediaPacket(header: MediaHeader(type: .inputAck, streamId: streamId, frameNo: 0), payload: ack.encode())
    }
}
