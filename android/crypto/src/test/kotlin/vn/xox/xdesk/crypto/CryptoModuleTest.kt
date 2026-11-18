package vn.xox.xdesk.crypto

import org.junit.Assert.assertEquals
import org.junit.Test

class CryptoModuleTest {
    @Test
    fun moduleNameIsStable() {
        assertEquals("crypto", CryptoModule.NAME)
    }
}
