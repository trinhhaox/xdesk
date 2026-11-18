package vn.xox.xdesk.media

import org.junit.Assert.assertEquals
import org.junit.Test

class MediaModuleTest {
    @Test
    fun moduleNameIsStable() {
        assertEquals("media", MediaModule.NAME)
    }
}
