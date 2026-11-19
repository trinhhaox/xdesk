package vn.xox.xdesk.transport

import vn.xox.xdesk.wire.MediaPacket

/**
 * Nơi nhận gói audio (ptype 0x20) của một phiên viewer. [ViewerSession] gọi [start] khi host đã thương lượng audio,
 * [onPacket] trên luồng nhận UDP (phải nhanh, không chặn) và [stop] khi phiên kết thúc.
 */
interface AudioSink {
    fun start()
    fun onPacket(packet: MediaPacket)
    fun stop()
}
