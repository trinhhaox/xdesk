package vn.xox.xdesk.media

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MediaLogicTest {
    private fun codec(name: String, hw: Boolean = true, sw: Boolean = false, alias: Boolean = false, ll: Boolean = false) =
        CodecCandidate(name, hw, sw, alias, ll)

    @Test
    fun selectorPrefersHardwareOverGenericSoftware() {
        val chosen = CodecSelector.select(listOf(codec("c2.android.avc.decoder", hw = false, sw = true), codec("c2.qti.avc.decoder")))
        assertEquals("c2.qti.avc.decoder", chosen?.name)
    }

    @Test
    fun selectorPrefersLowLatencyAmongHardwareAndKeepsSystemOrderOnTies() {
        assertEquals("b", CodecSelector.select(listOf(codec("a"), codec("b", ll = true)))?.name)
        assertEquals("a", CodecSelector.select(listOf(codec("a"), codec("b")))?.name)
    }

    @Test
    fun selectorFallsBackToSoftwareWhenNoHardwareAndSkipsAliases() {
        assertEquals("OMX.google.h264.decoder", CodecSelector.select(listOf(codec("OMX.google.h264.decoder", hw = false, sw = true)))?.name)
        assertEquals("real", CodecSelector.select(listOf(codec("alias", alias = true), codec("real")))?.name)
        assertNull(CodecSelector.select(emptyList()))
    }

    @Test
    fun quirksMatchByPrefixIgnoringCase() {
        assertEquals(1, DecoderQuirks.forCodec("c2.qti.avc.decoder.low_latency")?.lowLatencyKeys?.size)
        assertTrue(DecoderQuirks.forCodec("OMX.MTK.VIDEO.DECODER.AVC")?.mayHoldFrames == true)
        assertNull(DecoderQuirks.forCodec("c2.unknownvendor.avc.decoder"))
    }

    @Test
    fun lagMeterReportsPercentilesAndFramesHeld() {
        val meter = FrameLagMeter(windowSize = 4)
        // Decoder giữ 2 frame: vào 0,1,2,3 (mỗi 10 ms); ra sau 25 ms với 2 frame còn kẹt.
        listOf(0L, 1, 2, 3).forEach { meter.onInput(it, it * 10_000_000) }
        assertNull(meter.onOutput(0, 25_000_000))
        assertNull(meter.onOutput(1, 35_000_000))
        assertNull(meter.onOutput(2, 45_000_000))
        val report = assertNotNull(meter.onOutput(3, 55_000_000))
        assertEquals(4, report.samples)
        assertEquals(25.0, report.p50Ms)
        assertEquals(25.0, report.maxMs)
        assertEquals(3, report.maxFramesHeld)
    }

    @Test
    fun lagMeterIgnoresUnknownAndDroppedFrames() {
        val meter = FrameLagMeter(windowSize = 1)
        meter.onInput(5, 0)
        meter.onDropped(5)
        assertNull(meter.onOutput(5, 10))
        assertNull(meter.onOutput(99, 10))
    }
}
