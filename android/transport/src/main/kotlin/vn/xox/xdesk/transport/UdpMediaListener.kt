package vn.xox.xdesk.transport

import vn.xox.xdesk.wire.AssembledFrame
import vn.xox.xdesk.wire.MediaPacket

/** Sự kiện của kênh media; gọi trên thread I/O của kênh, nên xử lý nhanh (đưa vào hàng đợi). */
interface UdpMediaListener {
    fun onFrame(frame: AssembledFrame)
    /** Phải bỏ frame: người gọi gửi `keyframe.request` qua control. */
    fun onKeyframeNeeded()
    /** Gói không phải video/NACK (input-ack...). */
    fun onPacket(packet: MediaPacket)
    /** Không có gói hợp lệ nào suốt [UdpMediaChannel.LINK_TIMEOUT_MS]. */
    fun onLinkLost()
}
