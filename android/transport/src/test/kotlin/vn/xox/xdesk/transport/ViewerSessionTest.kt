package vn.xox.xdesk.transport

import java.util.concurrent.CopyOnWriteArrayList
import kotlin.io.path.createTempFile
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import vn.xox.xdesk.crypto.DeviceIdentity
import vn.xox.xdesk.crypto.PairingURI
import vn.xox.xdesk.wire.AssembledFrame
import vn.xox.xdesk.wire.Capabilities
import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.Packetizer

class ViewerSessionTest {
    private val host = FakeHost()
    private val frames = CopyOnWriteArrayList<AssembledFrame>()
    private val identity = DeviceIdentity.generate()
    private val store = FileKnownHostStore(createTempFile("hosts", ".txt").toFile().also { it.deleteOnExit() })
    private val approvalEvents = CopyOnWriteArrayList<AgentApprovalRequest?>()
    private val session = ViewerSession(ViewerTrust(identity, store), "Android-test", frames::add, onAgentApproval = approvalEvents::add)
    private val target = ViewerTarget("127.0.0.1", host.port)
    private val config = checkNotNull(DisplayConfigPlanner.config(1280.0, 720.0, 1.0))

    @AfterTest
    fun tearDown() {
        session.disconnect()
        host.close()
    }

    private fun qr() = PairingURI(host.identity.publicKey, host.token, listOf("127.0.0.1:${host.port}"))

    private fun await(what: String, timeoutMs: Long = 5000, cond: () -> Boolean) {
        val end = System.currentTimeMillis() + timeoutMs
        while (!cond()) {
            assertTrue(System.currentTimeMillis() < end, "hết giờ chờ: $what")
            Thread.sleep(10)
        }
    }

    private fun failedCode() = (session.state as? ViewerState.Failed)?.code

    @Test
    fun qrPairingStoresHostAndNegotiatesDisplay() {
        assertTrue(session.connect(listOf(target), config, ViewerAuth.Qr(qr())))
        assertEquals(ViewerState.Streaming, session.state)
        val known = store.all().single()
        assertEquals("FakeHost", known.name)
        assertContentEquals(host.identity.publicKey, known.publicKey)
        assertEquals("127.0.0.1:${host.port}", known.lastAddress)
        await("hello+display.config tới host") { host.received.any { it is ControlMessage.DisplayConfig } }
        val hello = host.received.filterIsInstance<ControlMessage.Hello>().single()
        val expected = Capabilities.H264 or Capabilities.HOT_RECONFIGURE or Capabilities.VIDEO_PAUSE or
            Capabilities.FILE_TRANSFER or Capabilities.REMOTE_UNLOCK or Capabilities.MEDIA_KEYS or Capabilities.MULTI_DISPLAY or
            Capabilities.WINDOW_CONTROL
        assertEquals(expected, hello.caps)
        assertEquals(1280L, host.received.filterIsInstance<ControlMessage.DisplayConfig>().single().w)
    }

    @Test
    fun ikReconnectUsesStoredKeyAndMeasuresRtt() {
        assertTrue(session.connect(listOf(target), config, ViewerAuth.Qr(qr())))
        session.disconnect()
        assertTrue(session.connect(listOf(target), config), "IK: ${session.state}")
        await("pong → rtt") { session.rttMs != null }
        assertEquals(1, store.all().size)
    }

    @Test
    fun ikWithUnknownViewerIsRefusedWithoutForgettingHost() {
        store.add("FakeHost", host.identity.publicKey, 1).let { store.setLastAddress(it.id, target.address) }
        assertTrue(!session.connect(listOf(target), config))
        assertEquals(TransportErrorCode.RECONNECT_REFUSED, failedCode())
        assertNotNull(session.refusedHostId)
        assertEquals(1, store.all().size)
    }

    @Test
    fun automaticWithoutPairingIsRejectedBeforeNetwork() {
        assertTrue(!session.connect(listOf(target), config))
        assertEquals(TransportErrorCode.PAIRING_REQUIRED, failedCode())
    }

    @Test
    fun qrWithWrongHostKeyIsPinned() {
        val forged = PairingURI(DeviceIdentity.generate().publicKey, host.token, listOf("127.0.0.1:${host.port}"))
        assertTrue(!session.connect(listOf(target), config, ViewerAuth.Qr(forged)))
        assertEquals(TransportErrorCode.HOST_KEY_MISMATCH, failedCode())
        assertTrue(store.all().isEmpty())
    }

    @Test
    fun sasPairingShowsSixDigitCode() {
        var code = ""
        assertTrue(session.connect(listOf(target), config, ViewerAuth.Sas { code = it.code; it.answer(true) }))
        assertTrue(Regex("\\d{3} \\d{3}").matches(code), code)
        assertEquals(1, store.all().size)
    }

    @Test
    fun sasMismatchOnTheViewerSavesNothingEvenThoughTheHostAccepted() {
        assertTrue(!session.connect(listOf(target), config, ViewerAuth.Sas { it.answer(false) }))
        assertEquals(TransportErrorCode.PAIRING_DENIED, failedCode())
        assertTrue(store.all().isEmpty())
    }

    @Test
    fun sasWaitsForTheViewersOwnConfirmation() {
        var prompt: SasPrompt? = null
        val confirmer = Thread {
            await("mã SAS") { prompt != null }
            Thread.sleep(300)
            assertTrue(store.all().isEmpty(), "host đồng ý thôi chưa đủ: chưa được lưu host")
            prompt?.answer(true)
        }
        confirmer.start()
        assertTrue(session.connect(listOf(target), config, ViewerAuth.Sas { prompt = it }))
        confirmer.join()
        assertEquals(1, store.all().size)
    }

    @Test
    fun revokedRejectEndsSessionAndForgetsHost() {
        host.revokeAfterReady = true
        assertTrue(session.connect(listOf(target), config, ViewerAuth.Qr(qr())))
        await("revoked") { session.state is ViewerState.Failed }
        assertEquals(TransportErrorCode.REVOKED_BY_HOST, failedCode())
        assertTrue(store.all().isEmpty())
    }

    private fun connectStreaming() = assertTrue(session.connect(listOf(target), config, ViewerAuth.Qr(qr())))

    private fun agentRequests() = host.received.filterIsInstance<ControlMessage.AgentApprove>()

    @Test
    fun agentApprovalIsSurfacedAndAnsweredOnceOverEncryptedChannel() {
        connectStreaming()
        val expiresAt = System.currentTimeMillis() + 60_000
        host.push(ControlMessage.AgentApprove("req-1", "Claude", "Mở TextEdit", expiresAt), id = 9)
        await("yêu cầu duyệt hiện lên") { session.pendingAgentApproval != null }
        val pending = checkNotNull(session.pendingAgentApproval)
        assertEquals("req-1", pending.id)
        assertEquals("Claude", pending.agentName)
        assertEquals("Mở TextEdit", pending.summary)
        session.answerAgentApproval(allow = true)
        session.answerAgentApproval(allow = false)
        await("trả lời tới host") { agentRequests().isNotEmpty() }
        Thread.sleep(150)
        assertEquals(listOf(ControlMessage.AgentApprove.response("req-1", true)), agentRequests())
        assertEquals(null, session.pendingAgentApproval)
        assertEquals(null, approvalEvents.last())
    }

    @Test
    fun agentApprovalExpiresOnItsOwnAndLateAnswerIsDropped() {
        connectStreaming()
        host.push(ControlMessage.AgentApprove("req-2", "Claude", "Bấm nút", System.currentTimeMillis() + 400))
        await("hiện lên") { session.pendingAgentApproval != null }
        await("tự hết hạn") { session.pendingAgentApproval == null }
        session.answerAgentApproval(allow = true)
        Thread.sleep(150)
        assertTrue(agentRequests().isEmpty())
    }

    @Test
    fun expiredOrResponseShapedAgentApproveIsIgnored() {
        connectStreaming()
        host.push(ControlMessage.AgentApprove("old", "Claude", "x", System.currentTimeMillis() - 1000))
        host.push(ControlMessage.AgentApprove.response("echo", true))
        host.push(ControlMessage.AgentApprove("good", "Claude", "y", System.currentTimeMillis() + 60_000))
        // AgentApprovalGate gán `current` trước khi gọi onChange: chờ cả hai, nếu không có thể đọc approvalEvents quá sớm.
        await("yêu cầu hợp lệ hiện lên") { session.pendingAgentApproval != null && approvalEvents.isNotEmpty() }
        assertEquals("good", session.pendingAgentApproval?.id)
        assertEquals(listOf("good"), approvalEvents.mapNotNull { it?.id })
    }

    @Test
    fun encryptedVideoFrameIsReassembledAndInputIsSent() {
        assertTrue(session.connect(listOf(target), config, ViewerAuth.Qr(qr())))
        val payload = ByteArray(5000) { (it % 251).toByte() }
        host.sendUdp({ sender ->
            Packetizer(1).packetize(byteArrayOf(0, 0, 0, 1) + payload, 7, 123, true).map { sender.seal(it.encode().copyOf(16), it.payload) }
        })
        await("frame") { frames.isNotEmpty() }
        val frame = frames.first()
        assertEquals(7L, frame.frameNo)
        assertTrue(frame.isKeyframe)
        assertContentEquals(byteArrayOf(0, 0, 0, 1) + payload, frame.data)
        assertEquals(0L, session.udpStats?.rejectedDatagramCount)
    }
}
