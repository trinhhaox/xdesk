package vn.xox.xdesk.crypto

/**
 * X25519 (RFC 7748) thuần Kotlin, dùng khi JCA không có "XDH" (Android API 31-32; XDH chỉ có từ API 33).
 * Chuyển thể từ thang Montgomery của TweetNaCl: 16 chi 16 bit, không rẽ nhánh theo bit bí mật (đổi chỗ bằng mặt nạ).
 */
internal object X25519Fallback {
    private val k121665 = longArrayOf(0xDB41, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    fun scalarMult(scalar: ByteArray, u: ByteArray): ByteArray {
        val z = scalar.copyOf(32)
        z[31] = ((z[31].toInt() and 127) or 64).toByte()
        z[0] = (z[0].toInt() and 248).toByte()
        val x = unpack(u)
        var a = LongArray(16).also { it[0] = 1 }
        var b = x.copyOf()
        var c = LongArray(16)
        var d = LongArray(16).also { it[0] = 1 }
        for (i in 254 downTo 0) {
            val r = (z[i ushr 3].toInt() ushr (i and 7)) and 1
            select(a, b, r); select(c, d, r)
            val e = add(a, c)
            a = sub(a, c); c = add(b, d); b = sub(b, d)
            d = mul(e, e)
            val f = mul(a, a)
            a = mul(c, a); c = mul(b, e)
            val e2 = add(a, c)
            a = sub(a, c); b = mul(a, a); c = sub(d, f)
            a = mul(c, k121665); a = add(a, d); c = mul(c, a); a = mul(d, f); d = mul(b, x); b = mul(e2, e2)
            select(a, b, r); select(c, d, r)
        }
        return pack(mul(a, invert(c)))
    }

    private fun unpack(n: ByteArray): LongArray {
        val o = LongArray(16) { (n[2 * it].toLong() and 0xFF) + ((n[2 * it + 1].toLong() and 0xFF) shl 8) }
        o[15] = o[15] and 0x7FFF
        return o
    }

    private fun carry(o: LongArray) {
        for (i in 0 until 16) {
            o[i] += 1L shl 16
            val c = o[i] shr 16
            if (i < 15) o[i + 1] += c - 1 else o[0] += c - 1 + 37 * (c - 1)
            o[i] -= c shl 16
        }
    }

    private fun select(p: LongArray, q: LongArray, bit: Int) {
        val mask = (bit - 1).toLong().inv()
        for (i in 0 until 16) {
            val t = mask and (p[i] xor q[i])
            p[i] = p[i] xor t
            q[i] = q[i] xor t
        }
    }

    private fun pack(n: LongArray): ByteArray {
        val t = n.copyOf()
        repeat(3) { carry(t) }
        val m = LongArray(16)
        repeat(2) {
            m[0] = t[0] - 0xFFED
            for (i in 1..14) {
                m[i] = t[i] - 0xFFFF - ((m[i - 1] shr 16) and 1)
                m[i - 1] = m[i - 1] and 0xFFFF
            }
            m[15] = t[15] - 0x7FFF - ((m[14] shr 16) and 1)
            val borrow = ((m[15] shr 16) and 1).toInt()
            m[14] = m[14] and 0xFFFF
            select(t, m, 1 - borrow)
        }
        val out = ByteArray(32)
        for (i in 0 until 16) {
            out[2 * i] = (t[i] and 0xFF).toByte()
            out[2 * i + 1] = (t[i] shr 8).toByte()
        }
        return out
    }

    private fun add(a: LongArray, b: LongArray) = LongArray(16) { a[it] + b[it] }
    private fun sub(a: LongArray, b: LongArray) = LongArray(16) { a[it] - b[it] }

    private fun mul(a: LongArray, b: LongArray): LongArray {
        val t = LongArray(31)
        for (i in 0 until 16) for (j in 0 until 16) t[i + j] += a[i] * b[j]
        for (i in 0 until 15) t[i] += 38 * t[i + 16]
        val o = t.copyOf(16)
        carry(o); carry(o)
        return o
    }

    private fun invert(i: LongArray): LongArray {
        var c = i.copyOf()
        for (a in 253 downTo 0) {
            c = mul(c, c)
            if (a != 2 && a != 4) c = mul(c, i)
        }
        return c
    }
}
