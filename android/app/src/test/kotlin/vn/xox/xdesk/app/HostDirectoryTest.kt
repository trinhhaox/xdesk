package vn.xox.xdesk.app

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import vn.xox.xdesk.app.discovery.DiscoveredHost
import vn.xox.xdesk.app.discovery.HostDirectory
import vn.xox.xdesk.app.discovery.HostStatus
import vn.xox.xdesk.transport.KnownHost
import vn.xox.xdesk.transport.ViewerTarget

class HostDirectoryTest {
    private fun known(id: String, name: String, address: String? = null) = KnownHost(id, name, ByteArray(32), address)
    private fun seen(id: String, name: String, host: String = "192.168.1.9") = DiscoveredHost(id, name, host, 47800)

    @Test
    fun everyPairedHostIsListedWithItsStatus() {
        val dir = HostDirectory.merge(
            listOf(known("A", "MacBook", "100.76.38.107:47800"), known("B", "Mac mini"), known("C", "iMac", "10.0.0.2:47800")),
            listOf(seen("C", "iMac")),
        )
        assertEquals(listOf("A", "B", "C"), dir.paired.map { it.known.id })
        assertEquals(HostStatus.ViaAddress("100.76.38.107:47800"), dir.paired[0].status)
        assertEquals("Qua địa chỉ 100.76.38.107:47800", dir.paired[0].status.label)
        assertEquals("Không thấy trên mạng", dir.paired[1].status.label)
        assertEquals("Sẵn sàng", dir.paired[2].status.label)
        assertTrue(dir.others.isEmpty())
    }

    @Test
    fun hostSeenAndSavedAppearsOnceAndUnpairedGoToOthers() {
        val dir = HostDirectory.merge(
            listOf(known("A", "MacBook", "100.76.38.107:47800")),
            listOf(seen("A", "MacBook"), seen("A", "MacBook", "fe80::1"), seen("Z", "Mac lạ"), seen("Z", "Mac lạ", "10.1.1.1")),
        )
        assertEquals(1, dir.paired.size)
        assertEquals(listOf("Z"), dir.others.map { it.id })
    }

    @Test
    fun connectTriesDiscoveredEndpointBeforeSavedAddress() {
        val both = HostDirectory.merge(listOf(known("A", "MacBook", "100.76.38.107:47800")), listOf(seen("A", "MacBook"))).paired.single()
        val targets = both.connectTargets()
        assertEquals(listOf("192.168.1.9:47800", "100.76.38.107:47800"), targets.map(ViewerTarget::address))
        assertEquals("A", targets[1].hostId)

        val savedOnly = HostDirectory.merge(listOf(known("A", "MacBook", "100.76.38.107:47800")), emptyList()).paired.single()
        assertEquals(listOf("100.76.38.107:47800"), savedOnly.connectTargets().map(ViewerTarget::address))
    }

    @Test
    fun sameEndpointIsNotTriedTwiceAndUnreachableHostHasNoTargets() {
        val same = HostDirectory.merge(listOf(known("A", "M", "192.168.1.9:47800")), listOf(seen("A", "M"))).paired.single()
        assertEquals(1, same.connectTargets().size)
        val none = HostDirectory.merge(listOf(known("B", "M2")), emptyList()).paired.single()
        assertTrue(none.connectTargets().isEmpty())
        assertNull(none.discovered)
    }
}
