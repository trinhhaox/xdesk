package vn.xox.xdesk.transport

import java.io.File
import kotlin.io.path.createTempDirectory
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import vn.xox.xdesk.crypto.DeviceIdentity
import vn.xox.xdesk.wire.InputEvent
import vn.xox.xdesk.wire.InputKind

class PureLogicTest {
    @Test
    fun sequencerAssignsSeqOnlyToReliableEventsAndResendsUntilAck() {
        val seq = InputSequencer()
        val out = seq.prepare(listOf(InputEvents.move(0.1f, 0.2f), InputEvents.button(true, 0.1f, 0.2f), InputEvents.key(4, true)), 0)
        assertEquals(listOf(0L, 1L, 2L), out.map { it.seq })
        assertTrue(seq.hasHeldInput)
        assertTrue(seq.resendDue(50).resend.isEmpty())
        assertEquals(2, seq.resendDue(100).resend.size)
        seq.acknowledge(1)
        assertEquals(1, seq.pendingCount)
        seq.prepare(listOf(InputEvents.key(4, false)), 100)
        seq.acknowledge(3)
        assertEquals(0, seq.pendingCount)
    }

    @Test
    fun sequencerAbandonsAfterMaxResends() {
        val seq = InputSequencer()
        seq.prepare(listOf(InputEvents.button(false, 0f, 0f)), 0)
        repeat(InputSequencer.MAX_RESENDS) { assertEquals(1, seq.resendDue(100L * (it + 1)).resend.size) }
        val last = seq.resendDue(100L * (InputSequencer.MAX_RESENDS + 1))
        assertEquals(1, last.abandoned.size)
        assertEquals(0, seq.pendingCount)
    }

    @Test
    fun heldInputTracksButtonsAndKeys() {
        val seq = InputSequencer()
        seq.prepare(listOf(InputEvents.button(true, 0f, 0f), InputEvents.key(7, true)), 0)
        seq.prepare(listOf(InputEvents.button(false, 0f, 0f)), 0)
        assertTrue(seq.hasHeldInput)
        seq.prepare(listOf(InputEvents.key(7, false)), 0)
        assertFalse(seq.hasHeldInput)
    }

    @Test
    fun batchesRespectWireLimitAndOrder() {
        val events = List(InputEvent.MAX_BATCH * 2 + 1) { InputEvents.scroll(it.toFloat(), 0f) }
        val batches = InputSequencer.batches(events)
        assertEquals(listOf(InputEvent.MAX_BATCH, InputEvent.MAX_BATCH, 1), batches.map { it.size })
        assertEquals(events, batches.flatten())
    }

    @Test
    fun sanitizedClampsPointerAndRejectsNonFinite() {
        assertEquals(1f, InputEvents.sanitized(InputEvents.move(5f, -1f))?.x)
        assertEquals(0f, InputEvents.sanitized(InputEvents.move(5f, -1f))?.y)
        assertNull(InputEvents.sanitized(InputEvents.scroll(Float.NaN, 0f)))
        assertEquals(InputKind.SCROLL, InputEvents.sanitized(InputEvents.scroll(300f, 0f))?.kind)
    }

    @Test
    fun clockSyncPicksLowestRttSampleAndRejectsInvalid() {
        val sync = ClockSync(windowSize = 3)
        assertFalse(sync.add(ClockSample(100, 50, 40, 110)))
        assertTrue(sync.add(ClockSample(0, 1010, 1011, 40)))
        assertTrue(sync.add(ClockSample(100, 1105, 1106, 110)))
        assertEquals(9L, sync.rttMs)
        assertEquals(1000.5, sync.offsetMs)
        assertEquals(1000L + 200, sync.viewerToHostMs(200)?.minus(1))
    }

    @Test
    fun displayConfigRoundsToEvenAndValidates() {
        val config = checkNotNull(DisplayConfigPlanner.config(1081.0, 721.0, 2.5))
        assertEquals(1082L, config.w)
        assertEquals(722L, config.h)
        assertNull(DisplayConfigPlanner.config(0.0, 720.0, 1.0))
        assertNull(DisplayConfigPlanner.config(Double.NaN, 720.0, 1.0))
        assertEquals(8.0, checkNotNull(DisplayConfigPlanner.config(100.0, 100.0, 99.0)).scale)
    }

    @Test
    fun textChunkerNeverSplitsSurrogatePairsAndKeepsBudget() {
        val text = "Việt Nam 😀".repeat(40)
        val chunks = TextChunker.splitUtf8(text, 16)
        assertEquals(text, chunks.joinToString(""))
        assertTrue(chunks.all { it.toByteArray().size <= 16 })
    }

    @Test
    fun viewerTargetParsesIpv4Ipv6AndRejectsGarbage() {
        assertEquals(ViewerTarget("192.168.1.5", 4000), ViewerTarget.parse(" 192.168.1.5:4000 "))
        assertEquals(ViewerTarget("fe80::1", 55), ViewerTarget.parse("[fe80::1]:55"))
        assertEquals("[fe80::1]:55", ViewerTarget("fe80::1", 55).address)
        listOf("host", "host:0", "host:99999", ":80", "[::1]80", "a:b:c").forEach { assertNull(ViewerTarget.parse(it), it) }
    }

    @Test
    fun viewerStatsComputesRatesAndLoss() {
        val stats = ViewerStats()
        assertNull(stats.closeWindow(0))
        listOf(0L, 1, 2, 4).forEach { stats.record(it, 1250) }
        val window = checkNotNull(stats.closeWindow(500))
        assertEquals(8, window.fps)
        assertEquals(80, window.recvKbps)
        assertEquals(200, window.lossPermille)
    }

    @Test
    fun knownHostStorePersistsUpdatesAndQuarantinesCorruption() {
        val dir = createTempDirectory("hosts").toFile()
        val file = File(dir, "hosts.txt")
        val key = DeviceIdentity.generate().publicKey
        val store = FileKnownHostStore(file)
        val host = store.add("Mac của Hào", key, 10)
        store.setLastAddress(host.id, "10.0.0.2:9000")
        store.markSeen(host.id, 99)
        val reloaded = FileKnownHostStore(file).all().single()
        assertEquals("Mac của Hào", reloaded.name)
        assertContentEquals(key, reloaded.publicKey)
        assertEquals("10.0.0.2:9000", reloaded.lastAddress)
        assertEquals(10L, reloaded.addedMs)
        assertEquals(99L, reloaded.lastSeenMs)
        assertTrue(FileKnownHostStore(file).remove(host.id))
        assertTrue(FileKnownHostStore(file).all().isEmpty())

        file.writeText("xdesk-known-hosts v1\nnot\ta\thost\n")
        val recovered = FileKnownHostStore(file)
        assertTrue(recovered.recoveredFromCorruption)
        assertTrue(recovered.all().isEmpty())
        assertTrue(File(dir, "hosts.txt.corrupt").exists())
    }

    @Test
    fun trustClassifiesPairedUnknownAndChangedKey() {
        val store = FileKnownHostStore(File(createTempDirectory("trust").toFile(), "h.txt"))
        val key = DeviceIdentity.generate().publicKey
        val paired = store.add("Mac A", key, 1)
        val trust = ViewerTrust(DeviceIdentity.generate(), store)
        assertTrue(trust.state(paired.id, "Mac A") is ViewerTrust.HostState.Paired)
        assertTrue(trust.state("0000-0000-0000-0000", "Mac A") is ViewerTrust.HostState.KeyChanged)
        assertTrue(trust.state("0000-0000-0000-0000", "Mac B") === ViewerTrust.HostState.Unknown)
        assertNull(trust.device("1.2.3.4:5"))
    }
}
