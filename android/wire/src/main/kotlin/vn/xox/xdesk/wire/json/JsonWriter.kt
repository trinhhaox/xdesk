package vn.xox.xdesk.wire.json

/** Ghi JSON ở dạng chuẩn của test vectors: khoá sắp xếp, không khoảng trắng, không escape `/`, UTF-8 thô. */
object JsonWriter {
    fun write(value: JsonValue): ByteArray = buildString { emit(value, this) }.toByteArray(Charsets.UTF_8)

    private fun emit(value: JsonValue, out: StringBuilder) {
        when (value) {
            JsonNull -> out.append("null")
            is JsonBool -> out.append(value.value)
            is JsonString -> string(value.value, out)
            is JsonNumber -> out.append(number(value))
            is JsonArray -> {
                out.append('[')
                value.items.forEachIndexed { index, item -> if (index > 0) out.append(','); emit(item, out) }
                out.append(']')
            }
            is JsonObject -> {
                out.append('{')
                value.fields.toSortedMap().entries.forEachIndexed { index, (key, item) ->
                    if (index > 0) out.append(',')
                    string(key, out)
                    out.append(':')
                    emit(item, out)
                }
                out.append('}')
            }
        }
    }

    private fun number(n: JsonNumber): String {
        n.long?.let { return it.toString() }
        require(n.double.isFinite()) { "non-finite number" }
        return n.exactLong()?.toString() ?: n.double.toString()
    }

    private fun string(text: String, out: StringBuilder) {
        out.append('"')
        for (c in text) {
            when {
                c == '"' -> out.append("\\\"")
                c == '\\' -> out.append("\\\\")
                c == '\n' -> out.append("\\n")
                c == '\r' -> out.append("\\r")
                c == '\t' -> out.append("\\t")
                c == '\b' -> out.append("\\b")
                c == '\u000C' -> out.append("\\f")
                c < ' ' -> out.append("\\u%04x".format(c.code))
                else -> out.append(c)
            }
        }
        out.append('"')
    }
}
