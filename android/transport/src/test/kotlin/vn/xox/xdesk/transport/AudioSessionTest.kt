package vn.xox.xdesk.transport

import java.util.concurrent.CopyOnWriteArrayList
import kotlin.io.path.createTempFile
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import vn.xox.xdesk.crypto.DeviceIdentity
import vn.xox.xdesk.crypto.PairingURI
import vn.xox.xdesk.wire.AudioCodec
import vn.xox.xdesk.wire.AudioPayload
import vn.xox.xdesk.wire.Capabilities
import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.MediaPacket

private class RecordingSink : AudioSink {
    val events = CopyOnWriteArrayList<String>()
    val packets = CopyOnWriteArrayList<MediaPacket>()
    override fun start() { events += "start" }
    override fun onPacket(packet: MediaPacket) { packets += packet }
    override fun stop() { events += "stop" }
}

class AudioSessionTest {
    private val host = FakeHost()
    private val sink = RecordingSink()
    private val store = FileKnownHostStore(createTempFile("hosts", ".txt").toFile().also { it.deleteOnExit() })
    private val session = ViewerSession(
        ViewerTrust(DeviceIdentity.generate(), store), "Android-test", { }, audioSink = sink,
    )
    private val target = ViewerTarget("127.0.0.1", host.port)
    private val config = checkNotNull(DisplayConfigPlanner.config(1280.0, 720.0, 1.0))

    @AfterTest
    fun tearDown() {
        session.disconnect()
        host.close()
    }

    private fun connect() = session.connect(listOf(target), config, ViewerAuth.Qr(PairingURI(host.identity.publicKey, host.token, listOf("127.0.0.1:${host.port}"))))

    private fun await(what: String, cond: () -> Boolean) {
        val end = System.currentTimeMillis() + 5000
        while (!cond()) {
            assertTrue(System.currentTimeMillis() < end, "hết giờ chờ: $what")
            Thread.sleep(10)
        }
    }

    @Test
    fun offersAudioCapsAndStartsSinkOnlyWhenNegotiated() {
        assertTrue(connect())
        await("hello") { host.received.any { it is ControlMessage.Hello } }
        val caps = host.received.filterIsInstance<ControlMessage.Hello>().single().caps
        assertEquals(Capabilities.H264 or Capabilities.AUDIO_PCM or Capabilities.AUDIO_AAC_ELD, caps)
        assertEquals(listOf("start"), sink.events.toList())
        session.disconnect()
        assertEquals(listOf("start", "stop"), sink.events.toList())
    }

    @Test
    fun encryptedAudioPacketReachesSink() {
        assertTrue(connect())
        val unit = ByteArray(80) { it.toByte() }
        val packet = AudioPayload(AudioCodec.AAC_ELD, 21, unit).mediaPacket(1, 4, 5000)
        host.sendUdp({ sender -> listOf(sender.seal(packet.encode().copyOf(16), packet.payload)) })
        await("audio packet") { sink.packets.isNotEmpty() }
        val received = AudioPayload.decode(sink.packets.first().payload)
        assertEquals(AudioCodec.AAC_ELD, received.codec)
        assertEquals(21, received.holdMs)
        assertContentEquals(unit, received.data)
    }
}
