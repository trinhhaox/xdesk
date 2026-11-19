package vn.xox.xdesk.crypto

import java.util.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import vn.xox.xdesk.wire.Hex

class CodecNegativeAndFuzzTest {
    private val host = ByteArray(32) { it.toByte() }
    private val token = ByteArray(32) { (it + 1).toByte() }

    private fun uri(vararg addresses: String) = PairingURI(host, token, addresses.toList()).string

    private fun rejects(text: String) =
        assertEquals(CryptoErrorCode.invalidPairingURI, assertFailsWith<CryptoException>(text) { PairingURI.parse(text) }.code)

    @Test
    fun pairingAddressValidation() {
        val good = listOf("10.0.0.1:1", "[::1]:65535", "[2001:db8::8a2e:370:7334]:80", "[::ffff:1.2.3.4]:80", "mac-mini.local:7878", "a.b:443")
        for (a in good) PairingURI.parse(uri(a))
        val bad = listOf(
            "10.0.0.1", "10.0.0.1:0", "10.0.0.1:65536", "10.0.0.1:80a", "01.2.3.4:80", "256.1.1.1:1", "[fe80::1%en0]:80",
            "::1:80", "[1:2:3:4:5:6:7:8:9]:80", "[1::2::3]:80", "host name:80", "user@host:80", "-bad.host:80", "http://h:80",
            "1.2.3.999:80", "host.123:80", ":80", "[]:80",
        )
        for (a in bad) {
            val ex = assertFailsWith<CryptoException>(a) { PairingURI(host, token, listOf(a)) }
            assertEquals(CryptoErrorCode.invalidPairingURI, ex.code)
        }
        assertFailsWith<CryptoException> { PairingURI(host, token, emptyList()) }
        assertFailsWith<CryptoException> { PairingURI(host, token, List(5) { "1.1.1.1:1" }) }
    }

    @Test
    fun pairingParseRejectsMalformedInput() {
        val h = "h=" + uri("1.1.1.1:1").substringAfter("h=").substringBefore('&')
        val t = "t=" + uri("1.1.1.1:1").substringAfter("t=").substringBefore('&')
        for (text in listOf(
            "xdesk://pair?$h&$t", "xdesk://pair?$h&$h&$t&a=1.1.1.1:1", "xdesk://other?$h&$t&a=1.1.1.1:1",
            "http://pair?$h&$t&a=1.1.1.1:1", "xdesk://pair/path?$h&$t&a=1.1.1.1:1", "xdesk://pair?$h&t=AAAA&a=1.1.1.1:1",
            "xdesk://pair?$h&$t=&a=1.1.1.1:1", "xdesk://pair?h=%ZZ&$t&a=1.1.1.1:1", "", "xdesk://pair?$h&$t&a=1.1.1.1:1&a=bad",
        )) rejects(text)
        val extra = PairingURI.parse("xdesk://pair?$h&$t&x=1&a=1.1.1.1:1")
        assertEquals(listOf("1.1.1.1:1"), extra.addresses)
        assertEquals("PairingURI(redacted, 1 addresses)", extra.toString())
    }

    @Test
    fun handshakeFramesAndPayloadsRejectGarbage() {
        for (hex in listOf("", "00", "0001", "000202", "000101ff", "01", "0100", "02", "03aa")) {
            assertFailsWith<CryptoException>(hex) { HandshakeFrame.decode(Hex.decode(hex)) }
        }
        for (hex in listOf("", "010000", "0102000000", "010000044d6163", "010000014dff", "0100020001", "01000041")) {
            assertFailsWith<CryptoException>(hex) { HandshakePayload.decode(Hex.decode(hex)) }
        }
        assertFailsWith<CryptoException> { HandshakePayload(DeviceRole.HOST, "x".repeat(65)).encode() }
    }

    @Test(timeout = 60_000)
    fun fuzzDecodersOnlyThrowCryptoException() {
        val random = Random(20261119)
        val receiver = DatagramReceiver(ByteArray(32) { 7 })
        val validUri = uri("10.0.0.1:7878", "[fe80::1]:7878").toByteArray()
        repeat(10_000) { i ->
            val bytes = ByteArray(random.nextInt(120)).also(random::nextBytes)
            val text = if (i % 2 == 0) String(bytes, Charsets.ISO_8859_1) else mutate(validUri, random)
            for (block in listOf<() -> Unit>(
                { HandshakeFrame.decode(bytes) }, { HandshakePayload.decode(bytes) }, { receiver.open(bytes) },
                { PairingURI.parse(text) }, { ShortAuthString.code(bytes, bytes) },
                { StreamReceiver(ByteArray(32)).open(2, bytes) },
            )) {
                try { block() } catch (_: CryptoException) { /* lỗi hợp lệ */ }
            }
        }
        assertTrue(true)
    }

    private fun mutate(seed: ByteArray, random: Random): String {
        val copy = seed.copyOf()
        repeat(1 + random.nextInt(3)) { copy[random.nextInt(copy.size)] = (32 + random.nextInt(95)).toByte() }
        return String(copy, Charsets.ISO_8859_1)
    }
}
