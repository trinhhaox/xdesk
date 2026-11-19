package vn.xox.xdesk.update

import com.sun.net.httpserver.HttpServer
import java.io.File
import java.net.InetSocketAddress
import java.security.MessageDigest
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Mô phỏng trọn luồng kiểm tra + tải + xác minh với manifest cục bộ (HTTP loopback, nên tiêm `requireHttps = false`). */
class UpdateFlowLocalServerTest {
    private val apk = ByteArray(300_000) { (it * 31).toByte() }
    private val apkSha = MessageDigest.getInstance("SHA-256").digest(apk).joinToString("") { "%02x".format(it) }
    private val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    private val base get() = "http://127.0.0.1:${server.address.port}"
    private var manifestBody = ""

    init {
        server.createContext("/android-update.json") { ex -> ex.sendResponseHeaders(200, 0).also { ex.responseBody.use { it.write(manifestBody.toByteArray()) } } }
        server.createContext("/apk") { ex -> ex.sendResponseHeaders(200, apk.size.toLong()).also { ex.responseBody.use { it.write(apk) } } }
        server.createContext("/moved") { ex -> ex.responseHeaders.add("Location", "/apk"); ex.sendResponseHeaders(302, -1); ex.close() }
        server.createContext("/boom") { ex -> ex.sendResponseHeaders(500, -1); ex.close() }
        server.start()
    }

    @AfterTest fun stop() = server.stop(0)

    private fun publish(versionCode: Long, apkPath: String = "/apk", sha: String = apkSha, size: Long = apk.size.toLong()) {
        manifestBody = manifestJson(versionCode = "$versionCode", apkUrl = "\"$base$apkPath\"", sha256 = "\"$sha\"", size = "$size")
    }

    private val http = UpdateHttp(requireHttps = false)
    private fun checker(installed: Long, store: MemoryStore = MemoryStore()) =
        UpdateChecker("$base/android-update.json", http::fetchBytes, store, { 42 }, installed, 34, requireHttps = false)

    @Test fun newerManifestIsAvailableThenDownloadsAndVerifies() {
        publish(versionCode = 2)
        val store = MemoryStore()
        val available = checker(installed = 1, store).check(manual = false) as CheckOutcome.Available
        assertEquals(42L, store.lastCheckMs)
        val dest = File.createTempFile("dl-", ".apk").also { it.deleteOnExit() }
        val progress = mutableListOf<Long>()
        http.download(available.manifest.apkUrl, dest, available.manifest.size) { done, _ -> progress += done }
        assertContentEquals(apk, dest.readBytes())
        assertTrue(progress.size > 1 && progress == progress.sorted() && progress.last() == apk.size.toLong())
        ApkIntegrity.verify(dest, available.manifest)
    }

    @Test fun sameOrOlderManifestIsUpToDate() {
        publish(versionCode = 2)
        assertEquals(CheckOutcome.UpToDate, checker(installed = 2).check(manual = true))
        assertEquals(CheckOutcome.UpToDate, checker(installed = 3).check(manual = true))
    }

    @Test fun redirectIsFollowed() {
        val dest = File.createTempFile("dl-", ".apk").also { it.deleteOnExit() }
        http.download("$base/moved", dest, apk.size.toLong()) { _, _ -> }
        assertEquals(apk.size.toLong(), dest.length())
    }

    @Test fun tamperedHashIsDetectedAfterDownload() {
        publish(versionCode = 2, sha = "0".repeat(64))
        val manifest = (checker(1).check(manual = true) as CheckOutcome.Available).manifest
        val dest = File.createTempFile("dl-", ".apk").also { it.deleteOnExit() }
        http.download(manifest.apkUrl, dest, manifest.size) { _, _ -> }
        assertEquals(UpdateFailure.HASH_MISMATCH, assertFailsWith<UpdateException> { ApkIntegrity.verify(dest, manifest) }.failure)
    }

    @Test fun serverSendingMoreThanDeclaredAbortsAndDeletesFile() {
        publish(versionCode = 2, size = 1000)
        val manifest = (checker(1).check(manual = true) as CheckOutcome.Available).manifest
        val dest = File.createTempFile("dl-", ".apk")
        assertEquals(UpdateFailure.SIZE_MISMATCH, assertFailsWith<UpdateException> { http.download(manifest.apkUrl, dest, manifest.size) { _, _ -> } }.failure)
        assertFalse(dest.exists())
    }

    @Test fun httpErrorAndGarbageManifestReportFailureWithoutRecordingCheck() {
        val store = MemoryStore()
        manifestBody = "garbage"
        assertTrue(checker(1, store).check(manual = true) is CheckOutcome.Failed)
        assertEquals(null, store.lastCheckMs)
        val failed = UpdateChecker("$base/boom", http::fetchBytes, store, { 42 }, 1, 34, requireHttps = false).check(manual = true)
        assertEquals(UpdateFailure.NETWORK, (failed as CheckOutcome.Failed).error.failure)
    }

    @Test fun httpsOnlyClientRefusesPlainHttp() {
        val e = assertFailsWith<UpdateException> { UpdateHttp().fetchBytes("$base/android-update.json", 1000) }
        assertEquals(UpdateFailure.INSECURE_URL, e.failure)
        assertFalse(e.message.orEmpty().contains("127.0.0.1"))
    }
}
