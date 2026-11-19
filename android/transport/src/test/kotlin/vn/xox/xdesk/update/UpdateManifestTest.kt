package vn.xox.xdesk.update

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class UpdateManifestTest {
    private fun parse(json: String) = UpdateManifest.parse(json.toByteArray())
    private fun failure(json: String) = assertFailsWith<UpdateException> { parse(json) }.failure

    @Test fun parsesValidManifest() {
        val m = parse(manifestJson())
        assertEquals(2, m.versionCode)
        assertEquals("0.1.1-beta", m.versionName)
        assertEquals(SHA_A, m.sha256)
        assertEquals(1234, m.size)
        assertEquals(31, m.minSdk)
        assertEquals("Sửa lỗi", m.releaseNotes)
    }

    @Test fun upperCaseShaIsNormalized() = assertEquals(SHA_A, parse(manifestJson(sha256 = "\"${SHA_A.uppercase()}\"")).sha256)

    @Test fun emptyReleaseNotesAllowed() = assertEquals("", parse(manifestJson(releaseNotes = "\"\"")).releaseNotes)

    @Test fun malformedJsonRejected() {
        for (bad in listOf("", "not json", "{", "[]", "null", "{\"versionCode\":2,}")) {
            assertEquals(UpdateFailure.MANIFEST_INVALID, failure(bad), bad)
        }
    }

    @Test fun invalidUtf8Rejected() {
        assertFailsWith<UpdateException> { UpdateManifest.parse(byteArrayOf(0x7B, 0xFF.toByte(), 0x7D)) }
    }

    @Test fun oversizeManifestRejected() {
        assertFailsWith<UpdateException> { UpdateManifest.parse(ByteArray(UpdateManifest.MAX_MANIFEST_BYTES + 1) { ' '.code.toByte() }) }
    }

    @Test fun everyMissingFieldRejected() {
        val keys = listOf("versionCode", "versionName", "apkUrl", "sha256", "size", "minSdk", "releaseNotes", "publishedAt")
        for (key in keys) {
            val json = manifestJson().replace(Regex("\"$key\":(\"[^\"]*\"|[0-9]+),?"), "").replace(",}", "}")
            assertEquals(UpdateFailure.MANIFEST_INVALID, failure(json), "thiếu $key")
        }
    }

    @Test fun wrongTypesRejected() {
        assertEquals(UpdateFailure.MANIFEST_INVALID, failure(manifestJson(versionCode = "\"2\"")))
        assertEquals(UpdateFailure.MANIFEST_INVALID, failure(manifestJson(versionCode = "2.5")))
        assertEquals(UpdateFailure.MANIFEST_INVALID, failure(manifestJson(versionName = "7")))
        assertEquals(UpdateFailure.MANIFEST_INVALID, failure(manifestJson(size = "\"1234\"")))
        assertEquals(UpdateFailure.MANIFEST_INVALID, failure(manifestJson(minSdk = "true")))
        assertEquals(UpdateFailure.MANIFEST_INVALID, failure(manifestJson(releaseNotes = "null")))
        assertEquals(UpdateFailure.MANIFEST_INVALID, failure(manifestJson(apkUrl = "5")))
    }

    @Test fun outOfRangeValuesRejected() {
        assertEquals(UpdateFailure.MANIFEST_INVALID, failure(manifestJson(versionCode = "0")))
        assertEquals(UpdateFailure.MANIFEST_INVALID, failure(manifestJson(versionCode = "-3")))
        assertEquals(UpdateFailure.MANIFEST_INVALID, failure(manifestJson(size = "0")))
        assertEquals(UpdateFailure.MANIFEST_INVALID, failure(manifestJson(size = "999999999999")))
        assertEquals(UpdateFailure.MANIFEST_INVALID, failure(manifestJson(minSdk = "0")))
        assertEquals(UpdateFailure.MANIFEST_INVALID, failure(manifestJson(versionName = "\"  \"")))
    }

    @Test fun badShaRejected() {
        assertEquals(UpdateFailure.MANIFEST_INVALID, failure(manifestJson(sha256 = "\"abc\"")))
        assertEquals(UpdateFailure.MANIFEST_INVALID, failure(manifestJson(sha256 = "\"${"g".repeat(64)}\"")))
    }

    @Test fun nonHttpsApkUrlRejected() {
        assertEquals(UpdateFailure.INSECURE_URL, failure(manifestJson(apkUrl = "\"http://example.test/x.apk\"")))
        assertEquals(UpdateFailure.INSECURE_URL, failure(manifestJson(apkUrl = "\"file:///sdcard/x.apk\"")))
        assertEquals(UpdateFailure.INSECURE_URL, failure(manifestJson(apkUrl = "\"https://\"")))
    }

    @Test fun errorMessagesNeverContainUrl() {
        val e = assertFailsWith<UpdateException> { parse(manifestJson(apkUrl = "\"http://secret.example/x.apk?token=abc\"")) }
        assert(!e.message.orEmpty().contains("secret.example"))
    }
}
