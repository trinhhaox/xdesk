package vn.xox.xdesk.app

import java.io.File
import javax.crypto.KeyGenerator
import kotlin.io.path.createTempDirectory
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import vn.xox.xdesk.app.discovery.DiscoveredHost
import vn.xox.xdesk.app.discovery.HostBadge
import vn.xox.xdesk.app.identity.IdentityUnavailableException
import vn.xox.xdesk.app.identity.WrappedKeyCodec
import vn.xox.xdesk.app.input.HidKeys
import vn.xox.xdesk.app.input.TextAction
import vn.xox.xdesk.app.input.TextInputBridge
import vn.xox.xdesk.app.ui.agentApprovalTitle
import vn.xox.xdesk.crypto.DeviceIdentity
import vn.xox.xdesk.transport.FileKnownHostStore
import vn.xox.xdesk.transport.InputModifiers
import vn.xox.xdesk.transport.ViewerTrust

class AppLogicTest {
    @Test
    fun wrappedKeyRoundTripsAndRejectsTamperingOrWrongKey() {
        val gen = KeyGenerator.getInstance("AES").apply { init(256) }
        val key = gen.generateKey()
        val secret = ByteArray(32) { it.toByte() }
        val blob = WrappedKeyCodec.wrap(key, secret)
        assertEquals(1 + 12 + 32 + 16, blob.size)
        assertContentEquals(secret, WrappedKeyCodec.unwrap(key, blob))
        assertFailsWith<IdentityUnavailableException> { WrappedKeyCodec.unwrap(gen.generateKey(), blob) }
        assertFailsWith<IdentityUnavailableException> { WrappedKeyCodec.unwrap(key, blob.copyOf().also { it[20] = (it[20] + 1).toByte() }) }
        assertFailsWith<IdentityUnavailableException> { WrappedKeyCodec.unwrap(key, blob.copyOf(10)) }
        assertTrue(!blob.contentEquals(WrappedKeyCodec.wrap(key, secret)), "mỗi lần bọc dùng IV mới")
    }

    @Test
    fun telexCompositionIsSentOnlyWhenCommitted() {
        val bridge = TextInputBridge()
        assertTrue(bridge.setComposing("vie").isEmpty())
        assertTrue(bridge.setComposing("việ").isEmpty())
        assertEquals(listOf(TextAction.Insert("việt")), bridge.commit("việt"))
        assertEquals("", bridge.composingText)
        bridge.setComposing("nam")
        assertEquals(listOf(TextAction.Insert("nam")), bridge.finishComposing())
        assertTrue(bridge.finishComposing().isEmpty())
        assertTrue(bridge.commit("").isEmpty())
    }

    @Test
    fun backspaceEditsDraftWhileComposingElseGoesToHost() {
        val bridge = TextInputBridge()
        bridge.setComposing("abc")
        assertTrue(bridge.deleteBefore(1).isEmpty())
        assertEquals("ab", bridge.composingText)
        assertEquals(listOf(TextAction.Insert("ab")), bridge.finishComposing())
        assertEquals(listOf(TextAction.Backspaces(2)), bridge.deleteBefore(2))
        assertTrue(bridge.deleteBefore(0).isEmpty())
    }

    @Test
    fun hidMappingCoversLettersDigitsKeysAndModifiers() {
        assertEquals(0x04, HidKeys.fromAndroid(29))
        assertEquals(0x1D, HidKeys.fromAndroid(54))
        assertEquals(0x1E, HidKeys.fromAndroid(8))
        assertEquals(0x27, HidKeys.fromAndroid(7))
        assertEquals(HidKeys.BACKSPACE, HidKeys.fromAndroid(67))
        assertEquals(HidKeys.ENTER, HidKeys.fromAndroid(66))
        assertEquals(0x3A, HidKeys.fromAndroid(131))
        assertNull(HidKeys.fromAndroid(0))
        assertEquals(InputModifiers.SHIFT or InputModifiers.COMMAND, HidKeys.modifiers(0x1 or 0x10000))
        assertEquals(InputModifiers.CONTROL or InputModifiers.OPTION, HidKeys.modifiers(0x1000 or 0x2))
    }

    @Test
    fun hostBadgeReflectsPairedUnknownAndChangedKey() {
        val store = FileKnownHostStore(File(createTempDirectory("badge").toFile(), "h.txt"))
        val paired = store.add("Mac A", DeviceIdentity.generate().publicKey, 1)
        val trust = ViewerTrust(DeviceIdentity.generate(), store)
        assertEquals(HostBadge.PAIRED, HostBadge.of(DiscoveredHost(paired.id, "Mac A", "10.0.0.1", 1), trust))
        assertEquals(HostBadge.KEY_CHANGED, HostBadge.of(DiscoveredHost("AAAA-AAAA-AAAA-AAAA", "Mac A", "10.0.0.1", 1), trust))
        assertEquals(HostBadge.UNPAIRED, HostBadge.of(DiscoveredHost("BBBB-BBBB-BBBB-BBBB", "Mac B", "10.0.0.2", 1), trust))
        assertEquals(listOf("Đã ghép", "Chưa ghép", "Khoá đã đổi"), HostBadge.entries.map { it.label })
    }

    @Test
    fun discoveredHostBuildsTargetWithIdAndName() {
        val target = DiscoveredHost("ID", "Mac", "10.0.0.5", 5555).toTarget()
        assertEquals("10.0.0.5:5555", target.address)
        assertEquals("ID", target.hostId)
    }

    @Test
    fun agentApprovalTitleNamesTheAgent() {
        assertEquals("Claude muốn điều khiển máy Mac", agentApprovalTitle("Claude"))
    }
}
