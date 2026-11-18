/// Cắt một access unit (video/audio) thành các gói UDP.
public struct Packetizer: Sendable {
    public let streamId: UInt16
    public let maxPayload: Int

    /// `maxPayload` được kẹp vào 1…1200.
    public init(streamId: UInt16, maxPayload: Int = MediaPacket.maxPayload) {
        self.streamId = streamId
        self.maxPayload = min(max(maxPayload, 1), MediaPacket.maxPayload)
    }

    public func packetize(
        frame: [UInt8], frameNo: UInt32, ptsMs: UInt32, isKeyframe: Bool = false, type: MediaPacketType = .video
    ) throws -> [MediaPacket] {
        guard !frame.isEmpty else { throw WireError.emptyPayload }
        guard type == .video || type == .audio else { throw WireError.unexpectedPacketType(type.rawValue) }
        let count = (frame.count + maxPayload - 1) / maxPayload
        guard count <= Int(MediaHeader.maxFragmentCount) else { throw WireError.fragmentCountTooLarge(UInt16(clamping: count)) }
        return (0..<count).map { idx in
            let start = idx * maxPayload
            let header = MediaHeader(
                type: type, streamId: streamId, frameNo: frameNo, fragIdx: UInt16(idx),
                fragCnt: UInt16(count), isKeyframe: isKeyframe, ptsMs: ptsMs
            )
            return MediaPacket(header: header, payload: Array(frame[start..<min(start + maxPayload, frame.count)]))
        }
    }
}
