package vn.xox.xdesk.transport

import java.util.concurrent.CopyOnWriteArrayList
import kotlin.io.path.createTempFile
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import vn.xox.xdesk.crypto.DeviceIdentity
import vn.xox.xdesk.crypto.PairingURI
import vn.xox.xdesk.wire.AssembledFrame
import vn.xox.xdesk.wire.Capabilities
import vn.xox.xdesk.wire.ClipKind
import vn.xox.xdesk.wire.ControlFrame
import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.MediaPacketType
import vn.xox.xdesk.wire.Packetizer

private class FakeClipboardAccess : ClipboardAccess {
    var current: ClipboardItem? = null
    val written = CopyOnWriteArrayList<ClipboardItem>()
    override fun read(): ClipboardItem? = current
    override fun write(item: ClipboardItem) {
        current = item
        written += item
    }
}

private class RecordingClipboardTransport : ClipboardTransport {
    val messages = CopyOnWriteArrayList<ControlMessage>()
    val sentData = CopyOnWriteArrayList<Pair<ControlMessage.ClipData, ByteArray>>()
    override fun sendClip(message: ControlMessage) { messages += message }
    override fun sendClipData(header: ControlMessage.ClipData, payload: ByteArray) {
        messages += header
        sentData += header to payload
    }
}

class MediaOverTcpAndClipboardTest {
    private val host = FakeHost()
    private val frames = CopyOnWriteArrayList<AssembledFrame>()
    private val store = FileKnownHostStore(createTempFile("hosts-mot", ".txt").toFile().also { it.deleteOnExit() })
    private val clipboard = FakeClipboardAccess()
    private val target = ViewerTarget("127.0.0.1", host.port)
    private val config = checkNotNull(DisplayConfigPlanner.config(1280.0, 720.0, 1.0))

    private fun qr() = PairingURI(host.identity.publicKey, host.token, listOf("127.0.0.1:${host.port}"))

    private fun await(what: String, timeoutMs: Long = 5000, cond: () -> Boolean) {
        val end = System.currentTimeMillis() + timeoutMs
        while (!cond()) {
            assertTrue(System.currentTimeMillis() < end, "hết giờ chờ: $what")
            Thread.sleep(10)
        }
    }

    @AfterTest
    fun tearDown() {
        host.close()
    }

    @Test
    fun mediaOverTcpReceivesProbeAndAssemblesFragmentedVideoFrames() {
        val session = ViewerSession(
            ViewerTrust(DeviceIdentity.generate(), store), "Android-usb", frames::add,
            clipboardAccess = clipboard, preferMediaOverTcp = true,
        )
        try {
            assertTrue(session.connect(listOf(target), config, ViewerAuth.Qr(qr())))
            assertTrue(session.clipboardAvailable)
            await("hello + probe qua MediaOverTcp") {
                host.received.any { it is ControlMessage.Hello } &&
                    host.receivedMediaOverTcp.any { it.header.type == MediaPacketType.PROBE }
            }
            val hello = host.received.filterIsInstance<ControlMessage.Hello>().single()
            assertTrue((hello.caps and Capabilities.MEDIA_OVER_TCP) != 0L)
            assertTrue((hello.caps and Capabilities.CLIPBOARD) != 0L)

            val payload = ByteArray(4500) { (it % 251).toByte() }
            val packets = Packetizer(1).packetize(byteArrayOf(0, 0, 0, 1) + payload, 0, 100, true)
            packets.forEach { host.pushMediaOverTcp(it) }

            await("frame video qua MediaOverTcp") { frames.isNotEmpty() }
            val frame = frames.first()
            assertEquals(0L, frame.frameNo)
            assertTrue(frame.isKeyframe)
            assertContentEquals(byteArrayOf(0, 0, 0, 1) + payload, frame.data)
        } finally {
            session.disconnect()
        }
    }

    @Test
    fun viewerSendsClipboardViaBulkFramesEndToEnd() {
        val session = ViewerSession(
            ViewerTrust(DeviceIdentity.generate(), store), "Android-clip", frames::add,
            clipboardAccess = clipboard,
        )
        try {
            assertTrue(session.connect(listOf(target), config, ViewerAuth.Qr(qr())))
            val bigText = "Xin chào Mac! ".repeat(6000) // > 64 KiB để kiểm tra chia chunk BULK
            clipboard.current = checkNotNull(ClipboardItem.text(bigText))

            var outcome: ClipboardSendOutcome? = null
            session.sendClipboard { outcome = it }
            await("clip.offer") { host.received.any { it is ControlMessage.ClipOffer } }
            assertEquals(ClipboardSendOutcome.Sent(ClipKind.TEXT), outcome)

            val offer = host.received.filterIsInstance<ControlMessage.ClipOffer>().single()
            assertEquals(clipboard.current!!.size, offer.size)
            assertEquals(clipboard.current!!.hash, offer.hash)

            host.push(ControlMessage.ClipPull(ClipKind.TEXT), id = 99)
            await("clip.data + 2 chunk BULK") {
                host.received.any { it is ControlMessage.ClipData } &&
                    host.receivedBulk.sumOf { it.size } == bigText.toByteArray(Charsets.UTF_8).size
            }
            assertTrue(host.receivedBulk.size >= 2)
            val reassembled = host.receivedBulk.reduce { a, b -> a + b }
            assertEquals(bigText, String(reassembled, Charsets.UTF_8))
        } finally {
            session.disconnect()
        }
    }

    @Test
    fun clipboardSyncHandlesReceiveEchoSuppressionAndValidation() {
        var now = 10_000L
        var enabled = true
        val access = FakeClipboardAccess()
        val transport = RecordingClipboardTransport()
        val sync = ClipboardSync(transport, access, echoWindowMs = 3000L, nowMs = { now }) { enabled }

        // Nhận clip.offer từ xa → gửi clip.pull → nhận clip.data + bulk nhiều mảnh
        val remoteItem = checkNotNull(ClipboardItem.text("Từ máy Mac sang Android"))
        sync.handle(ControlMessage.ClipOffer(ClipKind.TEXT, remoteItem.size, remoteItem.hash))
        assertEquals(listOf(ControlMessage.ClipPull(ClipKind.TEXT)), transport.messages.toList())

        sync.handle(ControlMessage.ClipData(ClipKind.TEXT, remoteItem.size, remoteItem.hash))
        val split = remoteItem.data.size / 2
        sync.handleBulk(remoteItem.data.copyOfRange(0, split))
        assertTrue(access.written.isEmpty())
        sync.handleBulk(remoteItem.data.copyOfRange(split, remoteItem.data.size))
        assertEquals(listOf(remoteItem), access.written.toList())

        // Trong cửa sổ echo 3s: bỏ qua clip.offer trùng hash vừa nhận
        transport.messages.clear()
        now += 1000L
        sync.handle(ControlMessage.ClipOffer(ClipKind.TEXT, remoteItem.size, remoteItem.hash))
        assertTrue(transport.messages.isEmpty())

        // Quá 3s: cho phép pull lại cùng nội dung
        now += 2500L
        sync.handle(ControlMessage.ClipOffer(ClipKind.TEXT, remoteItem.size, remoteItem.hash))
        assertEquals(listOf(ControlMessage.ClipPull(ClipKind.TEXT)), transport.messages.toList())

        // Hash sai không ghi vào clipboard
        sync.handle(ControlMessage.ClipData(ClipKind.TEXT, remoteItem.size, "f".repeat(64)))
        sync.handleBulk(remoteItem.data)
        assertEquals(1, access.written.size)

        // Quyền tắt -> trả Disabled và không đọc
        enabled = false
        assertEquals(ClipboardSendOutcome.Disabled, sync.sendCurrent())

        // Kiểm tra PNG hợp lệ vs giả mạo
        val fakePng = ByteArray(16) { 1 }
        assertEquals(null, ClipboardItem.of(ClipKind.IMAGE, fakePng))
        val validPng = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01)
        assertNotNull(ClipboardItem.of(ClipKind.IMAGE, validPng))

        // Chunk max constant check
        assertEquals(65536, ControlFrame.MAX_BULK_PAYLOAD)
    }

    @Test
    fun clipboardDisabledWhenPermissionOff() {
        val noClip = ClipboardItem.text("test")
        clipboard.current = noClip
        val session = ViewerSession(ViewerTrust(DeviceIdentity.generate(), store), "Android-noclip", frames::add)
        assertFalse(session.clipboardAvailable)
        var outcome: ClipboardSendOutcome? = null
        session.sendClipboard { outcome = it }
        assertEquals(ClipboardSendOutcome.Disabled, outcome)
    }
}
