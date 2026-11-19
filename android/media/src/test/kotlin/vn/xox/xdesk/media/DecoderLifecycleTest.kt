package vn.xox.xdesk.media

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class DecoderLifecycleTest {
    private val surface = Any()
    private val key = DecoderKey(surface, 1280, 720, emptyMap())

    @Test fun `khong configure khi surface da chet`() {
        assertEquals(StartPlan.SKIP_NO_SURFACE, DecoderLifecycle.plan(null, key, surfaceValid = false))
        assertEquals(StartPlan.SKIP_NO_SURFACE, DecoderLifecycle.plan(key, key, surfaceValid = false))
    }

    @Test fun `chua co codec thi start`() {
        assertEquals(StartPlan.START, DecoderLifecycle.plan(null, key, surfaceValid = true))
    }

    @Test fun `yeu cau trung cau hinh thi bo qua`() {
        assertEquals(StartPlan.SKIP_UNCHANGED, DecoderLifecycle.plan(key, key.copy(), surfaceValid = true))
    }

    @Test fun `doi co hoac surface thi huy codec cu roi dung lai`() {
        assertEquals(StartPlan.RESTART, DecoderLifecycle.plan(key, key.copy(width = 1920), surfaceValid = true))
        assertEquals(StartPlan.RESTART, DecoderLifecycle.plan(key, key.copy(surface = Any()), surfaceValid = true))
        assertEquals(StartPlan.RESTART, DecoderLifecycle.plan(key, key.copy(extra = mapOf("max-width" to 2560)), surfaceValid = true))
    }

    @Test fun `mo ta loi khong bao gio la null`() {
        assertEquals("IllegalArgumentException", DecoderLifecycle.describe(IllegalArgumentException()))
        assertEquals("IllegalStateException: sai trang thai", DecoderLifecycle.describe(IllegalStateException("sai trang thai")))
        assertEquals("IllegalStateException: diag, code=-38", DecoderLifecycle.describe(IllegalStateException("diag"), "code=-38"))
        assertFalse(DecoderLifecycle.describe(RuntimeException(" ")).contains("null"))
    }
}
