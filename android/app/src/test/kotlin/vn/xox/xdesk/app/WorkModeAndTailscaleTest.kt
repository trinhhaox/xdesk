package vn.xox.xdesk.app

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import vn.xox.xdesk.wire.ScreenMode

class WorkModeAndTailscaleTest {
    @Test fun workModeCoversFiveModesWithExpectedCategories() {
        assertEquals(5, WorkMode.entries.size)
        assertTrue(WorkMode.MIRROR.isVideoMode)
        assertTrue(WorkMode.EXTEND.isVideoMode)
        assertFalse(WorkMode.MIRROR.isControlMode)
        assertEquals(ScreenMode.MIRROR, WorkMode.MIRROR.screenMode)
        assertEquals(ScreenMode.EXTEND, WorkMode.EXTEND.screenMode)

        listOf(WorkMode.TRACKPAD, WorkMode.KEYBOARD, WorkMode.NUMPAD_MEDIA).forEach { mode ->
            assertTrue(mode.isControlMode, "$mode")
            assertFalse(mode.isVideoMode, "$mode")
            assertNull(mode.screenMode, "$mode")
        }

        WorkMode.entries.forEach { mode ->
            assertTrue(mode.title.isNotBlank(), "$mode")
            assertTrue(mode.shortTitle.isNotBlank(), "$mode")
            assertTrue(mode.summary.isNotBlank(), "$mode")
        }
    }

    @Test fun tailscaleHostDetectionMatchesCgnatUlaAndMagicDns() {
        assertTrue(TailscaleSupport.isTailscaleHost("100.64.0.1"))
        assertTrue(TailscaleSupport.isTailscaleHost("100.76.38.107:47800"))
        assertTrue(TailscaleSupport.isTailscaleHost(" 100.127.255.254 "))
        assertTrue(TailscaleSupport.isTailscaleHost("[fd7a:115c:a1e0::1]:47800"))
        assertTrue(TailscaleSupport.isTailscaleHost("fd7a:115c:a1e0::abcd"))
        assertTrue(TailscaleSupport.isTailscaleHost("macbook.tail1234.ts.net"))
        assertTrue(TailscaleSupport.isTailscaleHost("MacBook.Tail1234.ts.net:47800"))

        assertFalse(TailscaleSupport.isTailscaleHost("100.63.255.255"))
        assertFalse(TailscaleSupport.isTailscaleHost("100.128.0.1"))
        assertFalse(TailscaleSupport.isTailscaleHost("192.168.1.10:47800"))
        assertFalse(TailscaleSupport.isTailscaleHost("127.0.0.1"))
        assertFalse(TailscaleSupport.isTailscaleHost("example.com"))
        assertFalse(TailscaleSupport.isTailscaleHost(""))
    }
}
