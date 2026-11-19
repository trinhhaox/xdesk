package vn.xox.xdesk.transport.interop

import java.io.File
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import vn.xox.xdesk.crypto.DeviceIdentity
import vn.xox.xdesk.crypto.InMemoryIdentityStore
import vn.xox.xdesk.crypto.PairingURI
import vn.xox.xdesk.transport.DisplayConfigPlanner
import vn.xox.xdesk.transport.FileKnownHostStore
import vn.xox.xdesk.transport.ViewerSession
import vn.xox.xdesk.transport.ViewerState
import vn.xox.xdesk.transport.ViewerTarget
import vn.xox.xdesk.transport.ViewerTrust
import vn.xox.xdesk.wire.AssembledFrame

/** Đếm frame thật nhận được từ host Mac: tổng, keyframe, byte, và kiểm tra Annex B (start code + NAL type). */
class FrameCollector {
    val frames = AtomicInteger()
    val keyframes = AtomicInteger()
    val bytes = AtomicLong()
    val annexBValid = AtomicInteger()
    val idrInKeyframes = AtomicInteger()
    @Volatile var firstFrameAtMs = 0L

    fun accept(frame: AssembledFrame) {
        if (frames.getAndIncrement() == 0) firstFrameAtMs = System.currentTimeMillis()
        bytes.addAndGet(frame.data.size.toLong())
        if (frame.isKeyframe) keyframes.incrementAndGet()
        val nalTypes = nalUnitTypes(frame.data)
        if (nalTypes.isNotEmpty()) annexBValid.incrementAndGet()
        if (frame.isKeyframe && 5 in nalTypes) idrInKeyframes.incrementAndGet()
    }

    private fun nalUnitTypes(data: ByteArray): List<Int> {
        val types = ArrayList<Int>()
        var i = 0
        while (i + 3 < data.size) {
            val long = data[i] == 0.toByte() && data[i + 1] == 0.toByte() && data[i + 2] == 0.toByte() && data[i + 3] == 1.toByte()
            val short = data[i] == 0.toByte() && data[i + 1] == 0.toByte() && data[i + 2] == 1.toByte()
            val header = if (long) i + 4 else if (short) i + 3 else -1
            if (header in 0 until data.size) { types += data[header].toInt() and 0x1F; i = header } else i++
        }
        return types
    }
}

class InteropViewer(val name: String, hostsFile: File, identity: DeviceIdentity = DeviceIdentity.generate()) {
    val collector = FrameCollector()
    val trust = ViewerTrust(InMemoryIdentityStore(identity).loadOrCreate(), FileKnownHostStore(hostsFile))
    val session = ViewerSession(trust, name, collector::accept)

    fun connect(target: ViewerTarget, auth: vn.xox.xdesk.transport.ViewerAuth): Boolean {
        val config = DisplayConfigPlanner.config(1280.0, 720.0, 1.0, 60) ?: error("config")
        return session.connect(listOf(target), config, auth)
    }

    fun awaitFrames(seconds: Long): FrameCollector {
        val deadline = System.currentTimeMillis() + seconds * 1000
        while (System.currentTimeMillis() < deadline && session.state == ViewerState.Streaming) Thread.sleep(50)
        return collector
    }
}

object InteropEnv {
    fun uriFile(name: String): File? = System.getenv(name)?.takeIf { it.isNotBlank() }?.let(::File)?.takeIf { it.exists() }

    fun readUri(file: File): PairingURI = PairingURI.parse(file.readText().trim())

    /** Địa chỉ loopback của host: lấy cổng từ địa chỉ trong QR (QR có cả IP LAN lẫn 127.0.0.1). */
    fun loopback(uri: PairingURI): ViewerTarget {
        val port = uri.addresses.first().substringAfterLast(':').toInt()
        return ViewerTarget("127.0.0.1", port)
    }

    fun seconds(): Long = System.getenv("XDESK_INTEROP_SECONDS")?.toLongOrNull() ?: 5

    fun report(line: String) {
        println("INTEROP $line")
    }

    fun summary(c: FrameCollector, secs: Long) =
        "frames=${c.frames.get()} keyframes=${c.keyframes.get()} idrInKeyframes=${c.idrInKeyframes.get()} " +
            "annexB=${c.annexBValid.get()} bytes=${c.bytes.get()} avgKbps=${c.bytes.get() * 8 / (secs * 1000)}"
}
