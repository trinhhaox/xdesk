package vn.xox.xdesk.wire

import org.junit.Assert.assertEquals
import org.junit.Test

class WireModuleTest {
    @Test
    fun moduleNameIsStable() {
        assertEquals("wire", WireModule.NAME)
    }
}
