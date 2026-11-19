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
    fun lagMeterReportsPercentilesAndInFlight() {
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
        assertEquals(3, report.maxInFlight)
        assertEquals(0, report.stuckEvents)
    }

    @Test
    fun burstBacklogIsInFlightNotStuck() {
        // 6 frame tới cùng lúc (mạng giật), decoder xuất đều mỗi 5 ms: backlog lớn nhưng không có gì kẹt khi im lặng.
        val meter = FrameLagMeter(windowSize = 6)
        (0L..5).forEach { meter.onInput(it, 0) }
        (0L..4).forEach { assertNull(meter.onOutput(it, (it + 1) * 5_000_000)) }
        val report = assertNotNull(meter.onOutput(5, 30_000_000))
        assertEquals(5, report.maxInFlight)
        assertEquals(0, report.stuckEvents)
    }

    @Test
    fun framesLeftAfterQuietGapAreStuckAndExcludedFromLag() {
        // Decoder giữ 2 frame: sau khi im 500 ms vẫn còn 2 frame; frame kế vào mới đẩy chúng ra (sau 520 ms).
        val meter = FrameLagMeter(windowSize = 2)
        meter.onInput(-1, 0)
        assertNull(meter.onOutput(-1, 1_000_000)) // decoder đã ra frame đầu: hết giai đoạn khởi động
        meter.onInput(0, 2_000_000)
        meter.onInput(1, 12_000_000)
        meter.onInput(2, 512_000_000)
        assertNull(meter.onOutput(0, 522_000_000))
        assertNull(meter.onOutput(1, 523_000_000))
        val report = assertNotNull(meter.onOutput(2, 542_000_000))
        assertEquals(1, report.stuckEvents)
        assertEquals(2, report.maxStuckFrames)
        assertEquals(520.0, report.maxStuckLagMs)
        assertEquals(30.0, report.maxMs)
    }

    @Test
    fun framesTheDecoderSkippedAreNotCountedAsHeld() {
        // Decoder bỏ khung 1 và 2 rồi xuất 3: chúng đã mất, không phải đang kẹt; held phải về 0.
        val meter = FrameLagMeter(windowSize = 1)
        (0L..3).forEach { meter.onInput(it, it * 10_000_000) }
        val report = assertNotNull(meter.onOutput(3, 50_000_000))
        assertEquals(3, report.skipped)
        assertEquals(0, report.maxInFlight)
        assertEquals(0, meter.held)
        assertNull(meter.onOutput(1, 60_000_000))
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
