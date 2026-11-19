package vn.xox.xdesk.update

import java.io.File
import java.security.MessageDigest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ApkIntegrityTest {
    private val content = "xdesk apk bytes".toByteArray()
    private val contentSha = MessageDigest.getInstance("SHA-256").digest(content).joinToString("") { "%02x".format(it) }

    private fun tempFile(bytes: ByteArray = content) = File.createTempFile("apk", ".bin").also { it.writeBytes(bytes); it.deleteOnExit() }
    private fun manifest(sha: String = contentSha, size: Long = content.size.toLong()) = manifestOf().copy(sha256 = sha, size = size)

    @Test fun matchingFilePasses() = ApkIntegrity.verify(tempFile(), manifest())

    @Test fun sha256IsKnownVector() {
        val empty = tempFile(ByteArray(0))
        assertEquals("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", ApkIntegrity.sha256Hex(empty))
    }

    @Test fun flippedByteFailsHash() {
        val bad = content.copyOf().also { it[0] = (it[0].toInt() xor 1).toByte() }
        assertEquals(UpdateFailure.HASH_MISMATCH, assertFailsWith<UpdateException> { ApkIntegrity.verify(tempFile(bad), manifest()) }.failure)
    }

    @Test fun wrongSizeFailsBeforeHash() {
        assertEquals(UpdateFailure.SIZE_MISMATCH, assertFailsWith<UpdateException> { ApkIntegrity.verify(tempFile(), manifest(size = 3)) }.failure)
    }

    @Test fun signersMustBeIdenticalAndNonEmpty() {
        assertTrue(ApkIntegrity.signersMatch(setOf("a"), setOf("a")))
        assertFalse(ApkIntegrity.signersMatch(setOf("a"), setOf("b")))
        assertFalse(ApkIntegrity.signersMatch(setOf("a"), setOf("a", "b")))
        assertFalse(ApkIntegrity.signersMatch(emptySet(), emptySet()))
        assertFalse(ApkIntegrity.signersMatch(setOf("a"), emptySet()))
    }

    @Test fun certHashIsLowercaseHex() = assertEquals(64, ApkIntegrity.certSha256Hex(byteArrayOf(1, 2, 3)).length)
}
