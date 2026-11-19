package vn.xox.xdesk.crypto

/**
 * Địa chỉ ứng viên trong QR: `ipv4:port`, `[ipv6]:port` hoặc `hostname:port`, port 1…65535 (chỉ chữ số).
 * Từ chối mọi cú pháp khác (đường dẫn, `user@`, scheme, khoảng trắng, IPv6 không ngoặc, zone `%`).
 * Tự phân tích, không dùng `InetAddress` nên không bao giờ phát sinh truy vấn DNS.
 */
internal object HostPortAddress {
    fun isValid(text: String): Boolean {
        if (text.toByteArray(Charsets.UTF_8).size > PairingURI.MAX_ADDRESS_LENGTH) return false
        val (host, port, bracketed) = split(text) ?: return false
        val portNumber = port.takeIf { it.length in 1..5 && it.all { c -> c in '0'..'9' } }?.toInt() ?: return false
        if (portNumber !in 1..65535) return false
        return if (bracketed) isIPv6(host) else isIPv4(host) || isHostname(host)
    }

    private fun split(text: String): Triple<String, String, Boolean>? {
        if (text.startsWith("[")) {
            val close = text.indexOf(']')
            if (close < 0 || !text.startsWith(":", close + 1)) return null
            return Triple(text.substring(1, close), text.substring(close + 2), true)
        }
        val parts = text.split(':')
        return if (parts.size == 2) Triple(parts[0], parts[1], false) else null
    }

    private fun isIPv4(host: String): Boolean {
        val parts = host.split('.')
        return parts.size == 4 && parts.all { p ->
            p.length in 1..3 && p.all { it in '0'..'9' } && (p.length == 1 || p[0] != '0') && p.toInt() <= 255
        }
    }

    private fun isIPv6(host: String): Boolean {
        if (':' !in host || host.any { it != ':' && it != '.' && Character.digit(it, 16) < 0 }) return false
        val doubleColon = host.indexOf("::")
        if (doubleColon >= 0 && host.indexOf("::", doubleColon + 1) >= 0) return false
        val sides = if (doubleColon >= 0) listOf(host.substring(0, doubleColon), host.substring(doubleColon + 2)) else listOf(host)
        var groups = 0
        for ((index, side) in sides.withIndex()) {
            if (side.isEmpty()) continue
            val parts = side.split(':')
            for ((i, part) in parts.withIndex()) {
                val lastOfAddress = index == sides.lastIndex && i == parts.lastIndex
                when {
                    '.' in part -> if (lastOfAddress && isIPv4(part)) groups += 2 else return false
                    part.length in 1..4 -> groups++
                    else -> return false
                }
            }
        }
        return if (doubleColon >= 0) groups <= 7 else groups == 8
    }

    /** RFC 1123: nhãn 1…63 ký tự `[A-Za-z0-9-]`, không đầu/cuối `-`, tổng ≤ 253; nhãn cuối không thuần số. */
    private fun isHostname(host: String): Boolean {
        if (host.isEmpty() || host.length > 253) return false
        val labels = host.split('.')
        val valid = labels.all { l ->
            l.length in 1..63 && !l.startsWith('-') && !l.endsWith('-') &&
                l.all { it in '0'..'9' || it in 'a'..'z' || it in 'A'..'Z' || it == '-' }
        }
        return valid && !labels.last().all { it in '0'..'9' }
    }
}
