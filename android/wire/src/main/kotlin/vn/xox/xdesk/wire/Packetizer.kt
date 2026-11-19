package vn.xox.xdesk.wire

/** Cắt một access unit (video/audio) thành các gói UDP; `maxPayload` được kẹp vào 1…1192. */
class Packetizer(val streamId: Int, maxPayload: Int = MediaPacket.MAX_PAYLOAD) {
    val maxPayload: Int = maxPayload.coerceIn(1, MediaPacket.MAX_PAYLOAD)

    fun packetize(
        frame: ByteArray,
        frameNo: Long,
        ptsMs: Long,
        isKeyframe: Boolean = false,
        type: MediaPacketType = MediaPacketType.VIDEO,
    ): List<MediaPacket> {
        if (frame.isEmpty()) wireError(WireErrorCode.emptyPayload)
        if (type != MediaPacketType.VIDEO && type != MediaPacketType.AUDIO) wireError(WireErrorCode.unexpectedPacketType, "${type.raw}")
        val count = (frame.size + maxPayload - 1) / maxPayload
        if (count > MediaHeader.MAX_FRAGMENT_COUNT) wireError(WireErrorCode.fragmentCountTooLarge, "$count")
        return List(count) { idx ->
            val start = idx * maxPayload
            val header = MediaHeader(type, streamId, frameNo, idx, count, isKeyframe, ptsMs)
            MediaPacket(header, frame.copyOfRange(start, minOf(start + maxPayload, frame.size)))
        }
    }
}
