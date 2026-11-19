package vn.xox.xdesk.transport.interop

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import org.junit.Assume.assumeNotNull
import vn.xox.xdesk.transport.TransportErrorCode
import vn.xox.xdesk.transport.ViewerAuth
import vn.xox.xdesk.transport.ViewerState

/**
 * Thu hồi với host Mac THẬT (opt-in): `XDESK_INTEROP_REVOKE_URI_FILE` do host chạy kèm `--revoke-viewers-after <giây>` ghi.
 * Kỳ vọng: phiên bị cắt bằng `reject{revoked}` → host bị quên; IK kế tiếp với khoá cũ → `RECONNECT_REFUSED` (không tự quên).
 */
class MacHostRevokeInteropTest {
    private val uriFile = InteropEnv.uriFile("XDESK_INTEROP_REVOKE_URI_FILE")

    @Test
    fun revokedSessionIsCutAndHostForgotten() {
        assumeNotNull(uriFile)
        val file = checkNotNull(uriFile)
        val hosts = kotlin.io.path.createTempFile("known-hosts-revoke", ".txt").toFile().also { it.deleteOnExit() }
        val viewer = InteropViewer("Android-JVM-revoke", hosts)
        val uri = InteropEnv.readUri(file)
        val target = InteropEnv.loopback(uri)

        assertTrue(viewer.connect(target, ViewerAuth.Qr(uri)), "QR: ${viewer.session.state}")
        val known = viewer.trust.knownHosts.all().single()
        val connectedAt = System.currentTimeMillis()
        InteropEnv.report("revoke: paired, waiting for host to revoke")
        while (viewer.session.state == ViewerState.Streaming && System.currentTimeMillis() - connectedAt < 60_000) Thread.sleep(20)
        val cutAfterMs = System.currentTimeMillis() - connectedAt
        val state = viewer.session.state
        InteropEnv.report("revoke: cut after $cutAfterMs ms, state=${(state as? ViewerState.Failed)?.code}, frames=${viewer.collector.frames.get()}")
        assertTrue(state is ViewerState.Failed && state.code == TransportErrorCode.REVOKED_BY_HOST, "state=$state")
        assertEquals(0, viewer.trust.knownHosts.all().size, "host phải bị quên sau reject{revoked}")

        // IK với khoá cũ (UI chưa kịp xoá): host đóng im lặng → reconnectRefused, host KHÔNG tự bị quên.
        viewer.trust.knownHosts.add(known.name, known.publicKey, System.currentTimeMillis()).let { viewer.trust.knownHosts.setLastAddress(it.id, target.address) }
        val t = System.currentTimeMillis()
        assertTrue(!viewer.connect(target, ViewerAuth.Automatic))
        val failed = viewer.session.state as ViewerState.Failed
        InteropEnv.report("revoke: IK after revoke -> ${failed.code} in ${System.currentTimeMillis() - t} ms refusedHostId=${viewer.session.refusedHostId}")
        assertEquals(TransportErrorCode.RECONNECT_REFUSED, failed.code)
        assertNotNull(viewer.session.refusedHostId)
        assertEquals(1, viewer.trust.knownHosts.all().size, "không tự quên host khi IK bị từ chối")
    }
}
