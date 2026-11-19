package vn.xox.xdesk.media

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import java.nio.ByteBuffer
import java.nio.ByteOrder
import vn.xox.xdesk.wire.AudioPayload

/**
 * [AacEldUnitDecoder] bằng `MediaCodec` (`audio/mp4a-latm`, profile ELD) ở chế độ đồng bộ. `csd-0` là AudioSpecificConfig cố định
 * của giao thức (`AudioPayload.AAC_ELD_CONFIG`), nên không cần bên gửi báo cấu hình.
 * Một access unit vào → thường một khối PCM ra; bộ giải mã có thể trễ một khung khi mồi, khi đó trả mảng rỗng.
 */
class MediaCodecAacEldDecoder : AacEldUnitDecoder {
    private val codec: MediaCodec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
    private val info = MediaCodec.BufferInfo()
    private var presentationUs = 0L

    init {
        val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, AudioPayload.SAMPLE_RATE, AudioPayload.CHANNELS).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectELD)
            setInteger(MediaFormat.KEY_IS_ADTS, 0)
            setByteBuffer("csd-0", ByteBuffer.wrap(AudioPayload.AAC_ELD_CONFIG))
        }
        codec.configure(format, null, null, 0)
        codec.start()
    }

    override fun decode(unit: ByteArray): ShortArray {
        val inputIndex = codec.dequeueInputBuffer(INPUT_TIMEOUT_US)
        if (inputIndex < 0) return ShortArray(0)
        val input = checkNotNull(codec.getInputBuffer(inputIndex)) { "MediaCodec không cấp bộ đệm vào" }
        input.clear()
        input.put(unit)
        codec.queueInputBuffer(inputIndex, 0, unit.size, presentationUs, 0)
        presentationUs += FRAME_US
        return drain()
    }

    private fun drain(): ShortArray {
        var out = ShortArray(0)
        while (true) {
            val index = codec.dequeueOutputBuffer(info, OUTPUT_TIMEOUT_US)
            when {
                index >= 0 -> {
                    val buffer = checkNotNull(codec.getOutputBuffer(index)) { "MediaCodec không cấp bộ đệm ra" }
                    buffer.position(info.offset)
                    buffer.limit(info.offset + info.size)
                    val chunk = ShortArray(info.size / 2)
                    buffer.order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(chunk)
                    codec.releaseOutputBuffer(index, false)
                    out += chunk
                }
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> return out
                else -> Unit // đổi định dạng/bộ đệm ra: đọc tiếp
            }
        }
    }

    override fun release() {
        try {
            codec.stop()
        } catch (e: IllegalStateException) {
            // Codec đã lỗi: vẫn phải giải phóng.
        }
        codec.release()
    }

    private companion object {
        const val INPUT_TIMEOUT_US = 5_000L
        const val OUTPUT_TIMEOUT_US = 10_000L
        const val FRAME_US = AudioPayload.AAC_FRAMES_PER_UNIT * 1_000_000L / AudioPayload.SAMPLE_RATE
    }
}
