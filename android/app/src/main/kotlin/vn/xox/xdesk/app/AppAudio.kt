package vn.xox.xdesk.app

import vn.xox.xdesk.media.AudioPlayer
import vn.xox.xdesk.media.AudioTrackOutput
import vn.xox.xdesk.media.MediaCodecAacEldDecoder
import vn.xox.xdesk.transport.AudioSink
import vn.xox.xdesk.wire.MediaPacket

/** Nối `AudioPlayer` (AudioTrack độ trễ thấp + MediaCodec AAC-ELD) vào luồng nhận của `ViewerSession`. */
class AppAudio {
    val player = AudioPlayer(AudioTrackOutput()) { MediaCodecAacEldDecoder() }

    val sink: AudioSink = object : AudioSink {
        override fun start() = player.start()
        override fun onPacket(packet: MediaPacket) = player.ingest(packet)
        override fun stop() = player.stop()
    }
}
