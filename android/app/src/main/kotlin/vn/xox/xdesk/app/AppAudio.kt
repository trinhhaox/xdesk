package vn.xox.xdesk.app

import vn.xox.xdesk.media.AudioPlayer
import vn.xox.xdesk.media.AudioTrackOutput
import vn.xox.xdesk.media.MediaCodecAacEldDecoder
import vn.xox.xdesk.transport.AsyncAudioSink
import vn.xox.xdesk.transport.AudioSink
import vn.xox.xdesk.wire.MediaPacket

/** Nối `AudioPlayer` (AudioTrack độ trễ thấp + MediaCodec AAC-ELD) vào luồng nhận của `ViewerSession`. */
class AppAudio {
    val player = AudioPlayer(AudioTrackOutput()) { MediaCodecAacEldDecoder() }

    /** Giải mã trên luồng riêng: decoder chậm/treo không được chặn luồng UDP (keepalive), nếu không host cắt phiên sau 10 s. */
    val sink: AudioSink = AsyncAudioSink(object : AudioSink {
        override fun start() = player.start()
        override fun onPacket(packet: MediaPacket) = player.ingest(packet)
        override fun stop() = player.stop()
    })
}
