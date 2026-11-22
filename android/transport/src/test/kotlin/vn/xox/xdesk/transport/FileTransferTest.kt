package vn.xox.xdesk.transport

import java.io.ByteArrayInputStream
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.io.path.createTempDirectory
import kotlin.io.path.createTempFile
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import vn.xox.xdesk.crypto.DeviceIdentity
import vn.xox.xdesk.crypto.PairingURI
import vn.xox.xdesk.wire.ControlMessage

class FileTransferEngineTest {
    private val tempDir: File = createTempDirectory("xdesk-ft-test").toFile().also { it.deleteOnExit() }
    private val host = FakeHost()
    private val store = FileKnownHostStore(createTempFile("hosts-ft", ".txt").toFile().also { it.deleteOnExit() })
    private val target = ViewerTarget("127.0.0.1", host.port)
    private val config = checkNotNull(DisplayConfigPlanner.config(1280.0, 720.0, 1.0))

    @AfterTest
    fun tearDown() {
        host.close()
        tempDir.deleteRecursively()
    }

    @Test
    fun namingSanitizesPathTraversalAndDeduplicates() {
        assertEquals("passwd", FileTransferNaming.sanitizedName("../../etc/passwd"))
        assertEquals("file", FileTransferNaming.sanitizedName(".."))
        assertEquals("report.pdf", FileTransferNaming.sanitizedName("C:\\Users\\demo\\report.pdf"))

        val existing = setOf("photo.jpg", "photo (1).jpg")
        assertEquals("photo (2).jpg", FileTransferNaming.uniqueName("photo.jpg") { it in existing })
    }

    @Test
    fun receiverStreamsChunksVerifiesSha256AndHandlesCancel() {
        val completed = CopyOnWriteArrayList<FileTransferCompletion>()
        val failed = CopyOnWriteArrayList<Pair<String, String>>()
        val receiver = FileTransferReceiver(
            tempDirectory = tempDir,
            onCompleted = { completed += it },
            onFailed = { name, err -> failed += name to err },
        )

        val data = ByteArray(150_000) { (it % 251).toByte() }
        val hash = FileTransferNaming.sha256Hex(MessageDigest.getInstance("SHA-256").digest(data))
        receiver.handleStart(ControlMessage.FileStart("id-1", "test.bin", data.size.toLong()))

        var offset = 0
        while (offset < data.size) {
            val end = minOf(offset + 65_536, data.size)
            val chunk = data.copyOfRange(offset, end)
            receiver.handleChunkHeader(ControlMessage.FileChunk("id-1", chunk.size.toLong()))
            assertTrue(receiver.handleBulk(chunk))
            offset = end
        }
        receiver.handleDone(ControlMessage.FileDone("id-1", hash))
        assertEquals(1, completed.size)
        assertContentEquals(data, completed.single().file.readBytes())
        assertTrue(failed.isEmpty())

        // Cancel xoá .part sạch sẽ
        receiver.handleStart(ControlMessage.FileStart("id-2", "abort.zip", 100L))
        receiver.handleChunkHeader(ControlMessage.FileChunk("id-2", 4L))
        assertTrue(receiver.handleBulk(byteArrayOf(1, 2, 3, 4)))
        receiver.handleCancel(ControlMessage.FileCancel("id-2", "user cancelled"))
        assertTrue(tempDir.listFiles { _, name -> name.endsWith(".part") }?.isEmpty() == true)

        // Frame BULK không có file.chunk trước đó trả false (nhường lại cho Clipboard)
        assertFalse(receiver.handleBulk(byteArrayOf(9, 8, 7)))
    }

    @Test
    fun viewerStreamsMultiChunkFileToHostViaControlChannel() {
        val session = ViewerSession(ViewerTrust(DeviceIdentity.generate(), store), "Android-ft", {})
        try {
            assertTrue(session.connect(listOf(target), config, ViewerAuth.Qr(PairingURI(host.identity.publicKey, host.token, listOf("127.0.0.1:${host.port}")))))
            assertTrue(session.supportsFileTransfer)

            val payload = ByteArray(140_000) { (it % 199).toByte() }
            var finishOk = false
            session.sendFile("big.bin", payload.size.toLong(), { ByteArrayInputStream(payload) }) { ok, _ ->
                finishOk = ok
            }
            val deadline = System.currentTimeMillis() + 5000
            while (host.received.none { it is ControlMessage.FileDone } && System.currentTimeMillis() < deadline) {
                Thread.sleep(10)
            }
            assertTrue(finishOk || host.received.any { it is ControlMessage.FileDone })
            assertEquals(payload.size, host.receivedBulk.sumOf { it.size })
            assertEquals(3, host.receivedBulk.size) // 65536 + 65536 + 8928
        } finally {
            session.disconnect()
        }
    }
}
