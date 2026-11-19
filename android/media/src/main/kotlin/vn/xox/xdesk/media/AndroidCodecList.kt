package vn.xox.xdesk.media

import android.media.MediaCodecInfo
import android.media.MediaCodecList

/** Rút danh sách decoder cho một MIME từ MediaCodecList của máy (API 31+, nên `isHardwareAccelerated`/`isAlias` luôn có). */
object AndroidCodecList {
    const val MIME_AVC = "video/avc"

    fun decoders(mime: String = MIME_AVC): List<CodecCandidate> =
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
            .filter { !it.isEncoder && it.supportedTypes.any { type -> type.equals(mime, ignoreCase = true) } }
            .map { info ->
                CodecCandidate(
                    name = info.name,
                    isHardwareAccelerated = info.isHardwareAccelerated,
                    isSoftwareOnly = info.isSoftwareOnly,
                    isAlias = info.isAlias,
                    supportsLowLatency = info.getCapabilitiesForType(mime)
                        .isFeatureSupported(MediaCodecInfo.CodecCapabilities.FEATURE_LowLatency),
                )
            }
}
