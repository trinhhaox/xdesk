package vn.xox.xdesk.transport.interop

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.Assume.assumeNotNull
import vn.xox.xdesk.transport.InputEvents
import vn.xox.xdesk.transport.ViewerAuth
import vn.xox.xdesk.transport.ViewerState

/**
 * Interop với host Mac THẬT (opt-in): chỉ chạy khi `XDESK_INTEROP_URI_FILE` trỏ tới tệp do
 * `Xdesk --auto-host --auto-approve-pairing --print-pair-uri <tệp>` ghi. `./gradlew test` thường bỏ qua.
 */
class MacHostInteropTest {
    private val uriFile = InteropEnv.uriFile("XDESK_INTEROP_URI_FILE")
    private val secs = InteropEnv.seconds()

    @Test
    fun qrPairingThenIkReconnectThenSas() {
        assumeNotNull(uriFile)
        val file = checkNotNull(uriFile)
        val hosts = kotlin.io.path.createTempFile("known-hosts", ".txt").toFile().also { it.deleteOnExit() }
        val viewer = InteropViewer("Android-JVM-interop", hosts)

        // 1) Ghép đôi bằng QR (XXpsk3) qua 127.0.0.1.
        val uri = InteropEnv.readUri(file)
        val target = InteropEnv.loopback(uri)
        val t0 = System.currentTimeMillis()
        assertTrue(viewer.connect(target, ViewerAuth.Qr(uri)), "QR: ${viewer.session.state.describe()}")
        InteropEnv.report("QR pairing OK in ${System.currentTimeMillis() - t0} ms, hostKnown=${viewer.trust.knownHosts.all().size}")
        viewer.awaitFrames(secs)
        val c1 = viewer.collector
        InteropEnv.report("QR session ${InteropEnv.summary(c1, secs)} fps=${viewer.session.fps} recvKbps=${viewer.session.recvKbps}")
        InteropEnv.report("QR session rttMs=${viewer.session.rttMs} offsetMs=${viewer.session.clockOffsetMs} udp=${viewer.session.udpStats?.let { "rx=${it.datagramsReceived} rejected=${it.rejectedDatagramCount} malformed=${it.malformedPacketCount}" }}")
        assertTrue(c1.frames.get() > 0 && c1.keyframes.get() > 0 && c1.idrInKeyframes.get() > 0, "không nhận được frame/keyframe thật")
        assertEquals(c1.frames.get(), c1.annexBValid.get(), "mọi frame phải là Annex B hợp lệ")

        // 2) Input: move + key-up F13 (tin cậy → host phải input-ack).
        viewer.session.sendInput(listOf(InputEvents.move(0.5f, 0.5f), InputEvents.key(0x68, down = false)))
        Thread.sleep(600)
        InteropEnv.report("input sent, pendingAfter600ms=${viewer.session.pendingInputCount} (0 = host đã ack)")
        assertEquals(0, viewer.session.pendingInputCount, "host không ack input")
        viewer.session.disconnect()
        Thread.sleep(1500)

        // 3) Kết nối lại IK bằng khoá đã ghép.
        val t1 = System.currentTimeMillis()
        assertTrue(viewer.connect(target, ViewerAuth.Automatic), "IK: ${viewer.session.state.describe()}")
        InteropEnv.report("IK reconnect OK in ${System.currentTimeMillis() - t1} ms")
        val before = viewer.collector.frames.get()
        viewer.awaitFrames(secs)
        InteropEnv.report("IK session frames=${viewer.collector.frames.get() - before} total=${InteropEnv.summary(viewer.collector, secs * 2)}")
        assertTrue(viewer.collector.frames.get() > before, "IK không nhận frame")
        viewer.session.disconnect()
        Thread.sleep(1500)

        // 4) Ghép đôi bằng so mã SAS (XX + commitment), danh tính mới.
        val sasViewer = InteropViewer("Android-JVM-sas", kotlin.io.path.createTempFile("known-hosts", ".txt").toFile().also { it.deleteOnExit() })
        var code = ""
        assertTrue(sasViewer.connect(target, ViewerAuth.Sas { code = it }), "SAS: ${sasViewer.session.state.describe()}")
        InteropEnv.report("SAS pairing OK, code=$code (host --auto-approve-pairing tự Khớp)")
        sasViewer.awaitFrames(3)
        InteropEnv.report("SAS session ${InteropEnv.summary(sasViewer.collector, 3)}")
        assertTrue(sasViewer.collector.frames.get() > 0)
        sasViewer.session.disconnect()
    }

    private fun ViewerState.describe(): String = when (this) {
        is ViewerState.Failed -> "Failed($message, $code)"
        else -> this::class.simpleName.orEmpty()
    }
}
