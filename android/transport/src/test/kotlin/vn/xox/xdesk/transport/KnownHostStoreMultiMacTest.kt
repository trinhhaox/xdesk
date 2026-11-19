package vn.xox.xdesk.transport

import java.io.File
import kotlin.io.path.createTempDirectory
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNull
import vn.xox.xdesk.crypto.DeviceIdentity

class KnownHostStoreMultiMacTest {
    private fun store() = FileKnownHostStore(File(createTempDirectory("multi").toFile(), "hosts.txt"))

    @Test
    fun pairingSecondMacKeepsFirstWithItsOwnKeyAndAddress() {
        val store = store()
        val keyA = DeviceIdentity.generate().publicKey
        val keyB = DeviceIdentity.generate().publicKey
        val a = store.add("MacBook", keyA, 1)
        store.setLastAddress(a.id, "100.76.38.107:47800")
        val b = store.add("Mac mini", keyB, 2)
        store.setLastAddress(b.id, "100.64.0.9:47800")

        val all = store.all().associateBy { it.id }
        assertEquals(2, all.size)
        assertContentEquals(keyA, all.getValue(a.id).publicKey)
        assertContentEquals(keyB, all.getValue(b.id).publicKey)
        assertEquals("100.76.38.107:47800", all.getValue(a.id).lastAddress)
        val trust = ViewerTrust(DeviceIdentity.generate(), store)
        assertEquals(a.id, trust.device("100.76.38.107:47800")?.id)
        assertEquals(b.id, trust.device("100.64.0.9:47800")?.id)
    }

    @Test
    fun reassignedAddressMovesToLatestHostOnly() {
        val store = store()
        val a = store.add("Mac A", DeviceIdentity.generate().publicKey, 1)
        val b = store.add("Mac B", DeviceIdentity.generate().publicKey, 2)
        store.setLastAddress(a.id, "192.168.1.5:47800")
        store.setLastAddress(b.id, "192.168.1.5:47800")
        assertNull(store.all().first { it.id == a.id }.lastAddress)
        assertEquals("192.168.1.5:47800", store.all().first { it.id == b.id }.lastAddress)
        assertEquals(b.id, ViewerTrust(DeviceIdentity.generate(), store).device("192.168.1.5:47800")?.id)
    }

    @Test
    fun forgettingOneMacLeavesTheOther() {
        val store = store()
        val a = store.add("Mac A", DeviceIdentity.generate().publicKey, 1)
        val b = store.add("Mac B", DeviceIdentity.generate().publicKey, 2)
        store.remove(a.id)
        assertEquals(listOf(b.id), store.all().map { it.id })
    }
}
