package vn.xox.xdesk.crypto

import java.security.MessageDigest

/** URI trong QR ghép đôi: `xdesk://pair?h=<host pub b64url>&t=<token b64url>&a=<host:port>[&a=...]`. */
class PairingURI(val hostPublicKey: ByteArray, val token: ByteArray, val addresses: List<String>) {
    init {
        if (hostPublicKey.size != 32 || token.size != TOKEN_LENGTH || addresses.size !in 1..MAX_ADDRESSES ||
            !addresses.all(HostPortAddress::isValid)
        ) cryptoError(CryptoErrorCode.invalidPairingURI)
    }

    /** Địa chỉ đã validate chỉ chứa ký tự hợp lệ trong query, trừ `[` `]` cần %-encode (như URLComponents của Swift). */
    val string: String
        get() = buildString {
            append("xdesk://pair?h=").append(Base64Url.encode(hostPublicKey))
            append("&t=").append(Base64Url.encode(token))
            addresses.forEach { append("&a=").append(it.replace("[", "%5B").replace("]", "%5D")) }
        }

    override fun equals(other: Any?): Boolean = other is PairingURI &&
        MessageDigest.isEqual(token, other.token) && MessageDigest.isEqual(hostPublicKey, other.hostPublicKey) &&
        addresses == other.addresses

    override fun hashCode(): Int = addresses.hashCode()

    /** Không lộ token/khoá qua log. */
    override fun toString(): String = "PairingURI(redacted, ${addresses.size} addresses)"

    companion object {
        const val TOKEN_LENGTH = 32
        const val MAX_ADDRESSES = 4
        const val MAX_ADDRESS_LENGTH = 255
        private const val PREFIX = "xdesk://pair"

        fun parse(text: String): PairingURI {
            fun invalid(): Nothing = cryptoError(CryptoErrorCode.invalidPairingURI)
            if (!text.startsWith(PREFIX)) invalid()
            val rest = text.substring(PREFIX.length).substringBefore('#')
            if (rest.isNotEmpty() && !rest.startsWith("?")) invalid() // có path hoặc host dài hơn "pair"
            val items = rest.removePrefix("?").split('&').filter { it.isNotEmpty() }.map { item ->
                val name = item.substringBefore('=')
                val value = if ('=' in item) percentDecode(item.substringAfter('=')) ?: invalid() else null
                name to value
            }
            fun values(name: String) = items.filter { it.first == name }.mapNotNull { it.second }
            val hosts = values("h")
            val tokens = values("t")
            if (hosts.size != 1 || tokens.size != 1) invalid()
            return PairingURI(
                Base64Url.decode(hosts[0]) ?: invalid(), Base64Url.decode(tokens[0]) ?: invalid(), values("a"),
            )
        }

        private fun percentDecode(text: String): String? {
            val out = java.io.ByteArrayOutputStream()
            var i = 0
            while (i < text.length) {
                if (text[i] == '%') {
                    val digits = text.substring(i + 1, minOf(i + 3, text.length))
                    if (digits.length != 2 || digits.any { Character.digit(it, 16) < 0 }) return null
                    val byte = digits.toInt(16)
                    out.write(byte); i += 3
                } else {
                    out.write(text[i].toString().toByteArray(Charsets.UTF_8)); i++
                }
            }
            return try {
                Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(out.toByteArray())).toString()
            } catch (e: java.nio.charset.CharacterCodingException) { null }
        }
    }
}
