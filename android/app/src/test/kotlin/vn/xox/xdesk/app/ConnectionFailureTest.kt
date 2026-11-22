package vn.xox.xdesk.app

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import vn.xox.xdesk.app.input.PointerMode
import vn.xox.xdesk.app.ui.settingsSummary
import vn.xox.xdesk.transport.TransportErrorCode
import vn.xox.xdesk.wire.MirrorFit
import vn.xox.xdesk.wire.ScreenMode

class ConnectionFailureTest {
    private fun failure(code: TransportErrorCode?, message: String = "raw", host: String? = "MacBook Air của Trịnh") =
        ConnectionFailure(message, repairable = false, code = code, hostName = host)

    @Test fun timeoutNamesTheHostAndSuggestsWakingIt() {
        val text = failure(TransportErrorCode.TIMED_OUT).describe()
        assertEquals("MacBook Air của Trịnh không phản hồi.", text.title)
        assertTrue("Wi-Fi" in text.hint)
    }

    @Test fun refusedIsToldApartFromOtherConnectionFailures() {
        val refused = failure(TransportErrorCode.CONNECTION_FAILED, "Không kết nối được tới host: failed to connect to /127.0.0.1 (ECONNREFUSED)").describe()
        assertEquals("MacBook Air của Trịnh không nhận kết nối.", refused.title)
        val other = failure(TransportErrorCode.CONNECTION_FAILED, "Không kết nối được tới host: Socket closed").describe()
        assertEquals("Không kết nối được tới MacBook Air của Trịnh.", other.title)
    }

    @Test fun unreachableAndSlowConnectionFailuresGetSpecificSentences() {
        val unreachable = failure(TransportErrorCode.CONNECTION_FAILED, "failed to connect to /192.168.1.250 (port 47800) after 5000ms: isConnected failed: EHOSTUNREACH (No route to host)").describe()
        assertEquals("Không tìm thấy MacBook Air của Trịnh trên mạng này.", unreachable.title)
        val slow = failure(TransportErrorCode.CONNECTION_FAILED, "connect timed out").describe()
        assertEquals("MacBook Air của Trịnh không phản hồi.", slow.title)
    }

    @Test fun everyTransportCodeHasAVietnameseSentenceAndHint() {
        TransportErrorCode.entries.forEach { code ->
            val text = failure(code).describe()
            assertTrue(text.title.isNotBlank() && text.hint.isNotBlank(), "$code")
            assertFalse(text.title == "raw", "$code must not echo the technical message")
        }
    }

    @Test fun hostKeyChangeIsAWarningNotAnError() {
        assertTrue(failure(TransportErrorCode.HOST_KEY_MISMATCH).describe().warning)
        assertFalse(failure(TransportErrorCode.TIMED_OUT).describe().warning)
    }

    @Test fun pairingRelatedCodesPointToRepairing() {
        listOf(TransportErrorCode.PAIRING_REQUIRED, TransportErrorCode.RECONNECT_REFUSED, TransportErrorCode.REVOKED_BY_HOST).forEach {
            assertTrue("Ghép đôi" in failure(it).describe().hint, "$it")
        }
    }

    @Test fun missingHostNameFallsBackToGenericWording() {
        assertEquals("máy Mac không phản hồi.", failure(TransportErrorCode.TIMED_OUT, host = null).describe().title)
        assertEquals("máy Mac không phản hồi.", failure(TransportErrorCode.TIMED_OUT, host = " ").describe().title)
    }

    @Test fun failureWithoutCodeKeepsItsOwnMessageAndHasNoDetail() {
        val f = failure(null, "Địa chỉ phải có dạng host:port")
        assertEquals("Địa chỉ phải có dạng host:port", f.describe().title)
        assertNull(f.technicalDetail())
        assertEquals("raw", failure(TransportErrorCode.TIMED_OUT).technicalDetail())
    }

    @Test fun summaryListsModeFitAndPointer() {
        assertEquals("Chiếu màn hình Mac · Vừa với điện thoại · Chạm trực tiếp", settingsSummary(ScreenMode.MIRROR, MirrorFit.FIT_DEVICE, PointerMode.DIRECT))
        assertEquals("Màn hình phụ · Con trỏ", settingsSummary(ScreenMode.EXTEND, MirrorFit.FIT_DEVICE, PointerMode.TRACKPAD))
    }
}
