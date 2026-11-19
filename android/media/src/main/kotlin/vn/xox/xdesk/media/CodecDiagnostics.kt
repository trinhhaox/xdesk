package vn.xox.xdesk.media

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList

/** Chẩn đoán decoder trên máy thật: liệt kê mọi decoder H.264, tính năng được quảng bá và tham số vendor (API 31+). */
object CodecDiagnostics {
    fun listDecoders(log: (String) -> Unit) {
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
            .filter { !it.isEncoder && it.supportedTypes.any { t -> t.equals(AndroidCodecList.MIME_AVC, true) } }
            .forEach { info ->
                val caps = info.getCapabilitiesForType(AndroidCodecList.MIME_AVC)
                val features = FEATURES.filter { caps.isFeatureSupported(it) }
                log("decoder-list ${info.name} hw=${info.isHardwareAccelerated} sw=${info.isSoftwareOnly} alias=${info.isAlias} features=$features")
            }
    }

    fun vendorParameters(codec: MediaCodec, log: (String) -> Unit) {
        try {
            log("vendor-params ${codec.name} = ${codec.supportedVendorParameters}")
        } catch (e: IllegalStateException) {
            log("vendor-params không đọc được: ${e.message}")
        }
    }

    private val FEATURES = listOf(
        MediaCodecInfo.CodecCapabilities.FEATURE_LowLatency,
        MediaCodecInfo.CodecCapabilities.FEATURE_AdaptivePlayback,
        MediaCodecInfo.CodecCapabilities.FEATURE_SecurePlayback,
        MediaCodecInfo.CodecCapabilities.FEATURE_PartialFrame,
        MediaCodecInfo.CodecCapabilities.FEATURE_TunneledPlayback,
    )
}
