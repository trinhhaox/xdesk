package vn.xox.xdesk.app

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ViewportPolicyTest {
    @Test fun sameViewportKeepsSession() = assertFalse(ViewportPolicy.needsRenegotiation(false, 720 to 1600, 720 to 1600))

    @Test fun statusBarSizedGapIsRenegotiated() = assertTrue(ViewportPolicy.needsRenegotiation(false, 720 to 1600, 720 to 1544))

    @Test fun rotationIsRenegotiatedExceptInNativeMirror() {
        assertTrue(ViewportPolicy.needsRenegotiation(false, 720 to 1600, 1600 to 720))
        assertFalse(ViewportPolicy.needsRenegotiation(true, 720 to 1600, 1600 to 720))
    }

    @Test fun roundingToEvenPixelsIsTolerated() = assertFalse(ViewportPolicy.needsRenegotiation(false, 722 to 1600, 721 to 1600))

    @Test fun unknownSizesNeverRestart() = assertFalse(ViewportPolicy.needsRenegotiation(false, 0 to 0, 720 to 1600))
}
