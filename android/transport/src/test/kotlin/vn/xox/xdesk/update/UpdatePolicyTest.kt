package vn.xox.xdesk.update

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class UpdatePolicyTest {
    private val day = UpdatePolicy.CHECK_INTERVAL_MS

    @Test fun onlyStrictlyHigherVersionCodeApplies() {
        assertTrue(UpdatePolicy.isApplicable(manifestOf(versionCode = 2), 1, 34))
        assertFalse(UpdatePolicy.isApplicable(manifestOf(versionCode = 1), 1, 34))
        assertFalse(UpdatePolicy.isApplicable(manifestOf(versionCode = 1), 5, 34))
    }

    @Test fun minSdkRespected() {
        assertTrue(UpdatePolicy.isApplicable(manifestOf(minSdk = 31), 1, 31))
        assertTrue(UpdatePolicy.isApplicable(manifestOf(minSdk = 31), 1, 36))
        assertFalse(UpdatePolicy.isApplicable(manifestOf(minSdk = 34), 1, 33))
    }

    @Test fun throttleAllowsFirstCheck() = assertTrue(UpdatePolicy.shouldCheck(null, 1_000))

    @Test fun throttleBlocksWithin24h() {
        val last = 1_000_000L
        assertFalse(UpdatePolicy.shouldCheck(last, last))
        assertFalse(UpdatePolicy.shouldCheck(last, last + day - 1))
    }

    @Test fun throttleAllowsAt24hAndAfter() {
        val last = 1_000_000L
        assertTrue(UpdatePolicy.shouldCheck(last, last + day))
        assertTrue(UpdatePolicy.shouldCheck(last, last + 3 * day))
    }

    @Test fun clockRollbackAllowsCheck() = assertTrue(UpdatePolicy.shouldCheck(10 * day, day))

    @Test fun checkerHonoursThrottleButManualBypasses() {
        val store = MemoryStore(lastCheckMs = 5_000)
        var fetches = 0
        val checker = UpdateChecker("https://example.test/m.json", { _, _ -> fetches++; manifestJson().toByteArray() }, store, { 6_000 }, 1, 34)
        assertEquals(CheckOutcome.Throttled, checker.check(manual = false))
        assertEquals(0, fetches)
        assertTrue(checker.check(manual = true) is CheckOutcome.Available)
        assertEquals(1, fetches)
        assertEquals(6_000L, store.lastCheckMs)
    }
}
