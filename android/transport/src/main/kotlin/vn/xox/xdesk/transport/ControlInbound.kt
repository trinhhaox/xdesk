package vn.xox.xdesk.transport

import vn.xox.xdesk.crypto.StreamReceiver
import vn.xox.xdesk.wire.ControlEnvelope
import vn.xox.xdesk.wire.ControlFrame
import vn.xox.xdesk.wire.ControlFrameKind
import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.ControlMessageCodec
import vn.xox.xdesk.wire.MediaPacket

/** Thứ nhận được trên kênh điều khiển sau khi giải khung và giải mã. */
sealed interface ControlInbound {
    data class Message(val envelope: ControlEnvelope) : ControlInbound
    class MediaOverTcp(val packet: MediaPacket) : ControlInbound
    class Bulk(val bytes: ByteArray) : ControlInbound
}

/** Giải mã một frame đã nhận; `null` = bỏ qua (message `t` lạ, hoặc `rekey` đã được xử lý). */
internal fun decodeInbound(box: StreamReceiver, raw: ControlFrame): ControlInbound? {
    val payload = box.open(raw.kind.raw, raw.payload)
    return when (raw.kind) {
        ControlFrameKind.CONTROL -> {
            val envelope = ControlMessageCodec.decode(payload)
            when (envelope.message) {
                is ControlMessage.Unknown -> null
                ControlMessage.Rekey -> { box.rekey(); null }
                else -> ControlInbound.Message(envelope)
            }
        }
        ControlFrameKind.MEDIA_OVER_TCP -> ControlInbound.MediaOverTcp(MediaPacket.decode(payload))
        ControlFrameKind.BULK -> ControlInbound.Bulk(payload)
        ControlFrameKind.HANDSHAKE -> null
    }
}

/** Khoá UDP của phiên (dẫn xuất từ Noise). `toString` không lộ khoá. */
class UdpKeys(val send: ByteArray, val receive: ByteArray) {
    override fun toString(): String = "UdpKeys(redacted)"
}
