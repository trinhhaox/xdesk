package vn.xox.xdesk.transport

import org.junit.Assert.assertEquals
import org.junit.Test

class TransportModuleTest {
    @Test
    fun moduleNameIsStable() {
        assertEquals("transport", TransportModule.NAME)
    }
}
