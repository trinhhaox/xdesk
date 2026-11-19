package vn.xox.xdesk.crypto

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertTrue

/** Vector RFC 7748 §5.2, §6.1 và phép lặp; bản thuần Kotlin phải khớp bản JCA. */
class X25519FallbackTest {
    private fun hex(s: String) = ByteArray(s.length / 2) { s.substring(2 * it, 2 * it + 2).toInt(16).toByte() }

    @Test
    fun rfc7748Vectors() {
        assertContentEquals(
            hex("c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552"),
            X25519Fallback.scalarMult(
                hex("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4"),
                hex("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c"),
            ),
        )
        assertContentEquals(
            hex("95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957"),
            X25519Fallback.scalarMult(
                hex("4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d"),
                hex("e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493"),
            ),
        )
    }

    @Test
    fun rfc7748IteratedThousand() {
        var k = ByteArray(32).also { it[0] = 9 }
        var u = k.copyOf()
        for (i in 1..1000) {
            val next = X25519Fallback.scalarMult(k, u)
            u = k
            k = next
            if (i == 1) assertContentEquals(hex("422c8e7a6227d7bca1350b3e2bb7279f7897b87bb6854b783c60e80311ae3079"), k)
        }
        assertContentEquals(hex("684cf59ba83309552800ef566f2f4d3c1c3887c49360e3875f2eb94d99532c51"), k)
    }

    @Test
    fun diffieHellmanExample() {
        val alice = hex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
        val bobPublic = hex("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f")
        val base = ByteArray(32).also { it[0] = 9 }
        assertContentEquals(hex("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a"), X25519Fallback.scalarMult(alice, base))
        assertContentEquals(
            hex("4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"),
            X25519Fallback.scalarMult(alice, bobPublic),
        )
    }

    @Test
    fun fallbackMatchesJcaOnRandomKeys() {
        repeat(50) {
            val priv = Primitives.randomBytes(32)
            Primitives.preferJca = true
            val jca = Primitives.x25519PublicKey(priv)
            assertContentEquals(jca, X25519Fallback.scalarMult(priv, ByteArray(32).also { b -> b[0] = 9 }))
            assertTrue(Primitives.preferJca, "JVM thử nghiệm phải có XDH")
            val dhJca = Primitives.x25519(priv, jca)
            assertContentEquals(dhJca, X25519Fallback.scalarMult(priv, jca))
        }
    }
}
