package vn.xox.xdesk.app

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AwaitingFrameTest {
    @Test
    fun waitsForTheFirstFrameWhileStreamingNormally() {
        assertTrue(isAwaitingFrame(connecting = false, streaming = true, frameShown = false, hostVideoUnavailable = false))
        assertFalse(isAwaitingFrame(connecting = false, streaming = true, frameShown = true, hostVideoUnavailable = false))
    }

    @Test
    fun lockedMacNeverBlocksTheUnlockOverlayBehindAConnectingCard() {
        assertFalse(isAwaitingFrame(connecting = false, streaming = true, frameShown = false, hostVideoUnavailable = true))
    }

    @Test
    fun stillShowsConnectingWhileTheHandshakeRuns() {
        assertTrue(isAwaitingFrame(connecting = true, streaming = false, frameShown = false, hostVideoUnavailable = false))
    }
}
