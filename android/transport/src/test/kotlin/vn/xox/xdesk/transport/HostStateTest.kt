package vn.xox.xdesk.transport

import java.util.concurrent.CopyOnWriteArrayList
import kotlin.io.path.createTempFile
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import vn.xox.xdesk.crypto.DeviceIdentity
import vn.xox.xdesk.crypto.PairingURI
import vn.xox.xdesk.wire.ControlMessage

/** Host báo Mac khoá/tắt màn hình (`host.state`): phiên vẫn sống dù không có khung hình, và link UDP chỉ dựa vào gói hợp lệ bất kỳ. */
class HostStateTest {
    private val host = FakeHost()
    private val states = CopyOnWriteArrayList<ControlMessage.HostState>()
    private val store = FileKnownHostStore(createTempFile("hosts", ".txt").toFile().also { it.deleteOnExit() })
    private val session = ViewerSession(
        ViewerTrust(DeviceIdentity.generate(), store), "Android-test", {}, onHostState = states::add,
    )
    private val config = checkNotNull(DisplayConfigPlanner.config(1280.0, 720.0, 1.0))

    @AfterTest
    fun tearDown() {
        session.disconnect()
        host.close()
    }

    private fun await(what: String, timeoutMs: Long = 5000, cond: () -> Boolean) {
        val end = System.currentTimeMillis() + timeoutMs
        while (!cond()) {
            assertTrue(System.currentTimeMillis() < end, "hết giờ chờ: $what")
            Thread.sleep(10)
        }
    }

    @Test
    fun hostStateIsDeliveredAndSessionStaysStreamingWithoutFrames() {
        val qr = PairingURI(host.identity.publicKey, host.token, listOf("127.0.0.1:${host.port}"))
        assertTrue(session.connect(listOf(ViewerTarget("127.0.0.1", host.port)), config, ViewerAuth.Qr(qr)))
        host.push(ControlMessage.HostState(videoAvailable = false, locked = true))
        await("host.state tới viewer") { states.isNotEmpty() }
        assertEquals(ControlMessage.HostState(false, true), states.first())
        Thread.sleep(500)
        assertEquals(ViewerState.Streaming, session.state)
        host.push(ControlMessage.HostState(videoAvailable = true, locked = false))
        await("host.state hồi phục") { states.size == 2 }
        assertTrue(states.last().videoAvailable)
    }

    @Test
    fun linkHealthNeverReportsLossWhileAnyValidPacketKeepsArriving() {
        var now = 0L
        val health = LinkHealth { now }
        var lost = 0
        // 30 s không có khung hình nào, chỉ keepalive probe mỗi 2 s → mỗi probe là một gói hợp lệ.
        repeat(30) { second ->
            now = (second + 1) * 1000L
            if (second % 2 == 0) health.markValid()
            health.maintain(heardFromHost = true, sendProbe = {}, askResync = {}, onLinkLost = { lost++ })
        }
        assertEquals(0, lost)
    }

    @Test
    fun linkHealthReportsLossAfterTheTimeoutWhenNothingArrives() {
        var now = 0L
        val health = LinkHealth { now }
        var lost = 0
        repeat(12) { second ->
            now = (second + 1) * 1000L
            health.maintain(heardFromHost = true, sendProbe = {}, askResync = {}, onLinkLost = { lost++ })
        }
        assertEquals(1, lost)
        assertFalse(lost > 1)
    }
}
