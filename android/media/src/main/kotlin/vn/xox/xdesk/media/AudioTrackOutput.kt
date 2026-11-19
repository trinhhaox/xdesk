package vn.xox.xdesk.media

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import vn.xox.xdesk.wire.AudioPayload

/**
 * [PcmOutput] bằng `AudioTrack` chế độ độ trễ thấp (`PERFORMANCE_MODE_LOW_LATENCY`), 48 kHz s16 stereo, ghi chặn.
 * Bộ đệm của track chỉ lớn hơn mức tối thiểu của thiết bị đúng một chút để giữ trễ thấp mà không underrun ở thiết bị chậm.
 */
class AudioTrackOutput : PcmOutput {
    private var track: AudioTrack? = null

    override val outputLatencyMs: Int
        get() {
            val frames = track?.bufferSizeInFrames ?: return 0
            return frames * 1000 / AudioPayload.SAMPLE_RATE
        }

    override fun start() {
        if (track != null) return
        val format = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(AudioPayload.SAMPLE_RATE)
            .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
            .build()
        val minBytes = AudioTrack.getMinBufferSize(AudioPayload.SAMPLE_RATE, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT)
        check(minBytes > 0) { "thiết bị không hỗ trợ AudioTrack 48 kHz stereo (mã $minBytes)" }
        val created = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MOVIE).build(),
            )
            .setAudioFormat(format)
            .setBufferSizeInBytes(minBytes)
            .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        created.play()
        track = created
    }

    override fun write(samples: ShortArray) {
        val active = track ?: return
        var offset = 0
        while (offset < samples.size) {
            val written = active.write(samples, offset, samples.size - offset, AudioTrack.WRITE_BLOCKING)
            if (written <= 0) return
            offset += written
        }
    }

    override fun stop() {
        val active = track ?: return
        track = null
        try {
            active.stop()
        } catch (e: IllegalStateException) {
            // Track đã ngừng (vd. thiết bị ra bị rút): chỉ cần giải phóng.
        }
        active.release()
    }
}
