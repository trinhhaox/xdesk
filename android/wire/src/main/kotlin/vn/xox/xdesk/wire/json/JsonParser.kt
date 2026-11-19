package vn.xox.xdesk.wire.json

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

/** Lỗi cú pháp JSON; lớp gọi đổi thành `WireException(malformedJSON)`. */
class JsonSyntaxException(message: String) : Exception(message)

/** Parser JSON (RFC 8259) đệ quy có giới hạn độ sâu; chỉ ném `JsonSyntaxException`. */
object JsonParser {
    private const val MAX_DEPTH = 16

    fun parse(bytes: ByteArray): JsonValue {
        val text = try {
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes)).toString()
        } catch (e: CharacterCodingException) {
            throw JsonSyntaxException("invalid UTF-8")
        }
        return parse(text)
    }

    fun parse(text: String): JsonValue {
        val reader = Reader(text)
        val value = reader.value(0)
        reader.skipWhitespace()
        if (!reader.atEnd) throw JsonSyntaxException("trailing data")
        return value
    }

    private class Reader(private val s: String) {
        private var i = 0
        val atEnd: Boolean get() = i >= s.length

        fun skipWhitespace() {
            while (i < s.length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) i++
        }

        private fun fail(what: String): Nothing = throw JsonSyntaxException("$what at $i")

        private fun expect(c: Char) {
            if (i >= s.length || s[i] != c) fail("expected '$c'")
            i++
        }

        fun value(depth: Int): JsonValue {
            if (depth > MAX_DEPTH) fail("too deep")
            skipWhitespace()
            if (atEnd) fail("unexpected end")
            return when (val c = s[i]) {
                '{' -> obj(depth)
                '[' -> arr(depth)
                '"' -> JsonString(string())
                't' -> literal("true", JsonBool(true))
                'f' -> literal("false", JsonBool(false))
                'n' -> literal("null", JsonNull)
                else -> if (c == '-' || c in '0'..'9') number() else fail("unexpected '$c'")
            }
        }

        private fun literal(word: String, result: JsonValue): JsonValue {
            if (!s.startsWith(word, i)) fail("bad literal")
            i += word.length
            return result
        }

        private fun obj(depth: Int): JsonValue {
            expect('{')
            val fields = LinkedHashMap<String, JsonValue>()
            skipWhitespace()
            if (i < s.length && s[i] == '}') { i++; return JsonObject(fields) }
            while (true) {
                skipWhitespace()
                if (atEnd || s[i] != '"') fail("expected key")
                val key = string()
                skipWhitespace()
                expect(':')
                fields[key] = value(depth + 1)
                skipWhitespace()
                if (atEnd) fail("unexpected end")
                when (s[i++]) {
                    ',' -> continue
                    '}' -> return JsonObject(fields)
                    else -> fail("expected ',' or '}'")
                }
            }
        }

        private fun arr(depth: Int): JsonValue {
            expect('[')
            val items = ArrayList<JsonValue>()
            skipWhitespace()
            if (i < s.length && s[i] == ']') { i++; return JsonArray(items) }
            while (true) {
                items += value(depth + 1)
                skipWhitespace()
                if (atEnd) fail("unexpected end")
                when (s[i++]) {
                    ',' -> continue
                    ']' -> return JsonArray(items)
                    else -> fail("expected ',' or ']'")
                }
            }
        }

        private fun string(): String {
            expect('"')
            val out = StringBuilder()
            while (true) {
                if (atEnd) fail("unterminated string")
                val c = s[i++]
                when {
                    c == '"' -> return out.toString()
                    c < ' ' -> fail("control char in string")
                    c == '\\' -> out.append(escape())
                    else -> out.append(c)
                }
            }
        }

        private fun escape(): Char {
            if (atEnd) fail("bad escape")
            return when (val e = s[i++]) {
                '"', '\\', '/' -> e
                'b' -> '\b'
                'f' -> '\u000C'
                'n' -> '\n'
                'r' -> '\r'
                't' -> '\t'
                'u' -> {
                    if (i + 4 > s.length) fail("bad \\u escape")
                    val code = s.substring(i, i + 4).takeIf { h -> h.all { Character.digit(it, 16) >= 0 } }
                        ?.toInt(16) ?: fail("bad \\u escape")
                    i += 4
                    code.toChar()
                }
                else -> fail("bad escape")
            }
        }

        private fun number(): JsonValue {
            val start = i
            if (s[i] == '-') i++
            if (atEnd) fail("bad number")
            if (s[i] == '0') i++ else if (s[i] in '1'..'9') digits() else fail("bad number")
            var integral = true
            if (i < s.length && s[i] == '.') { i++; integral = false; digits() }
            if (i < s.length && (s[i] == 'e' || s[i] == 'E')) {
                i++; integral = false
                if (i < s.length && (s[i] == '+' || s[i] == '-')) i++
                digits()
            }
            val lexeme = s.substring(start, i)
            val asLong = if (integral) lexeme.toLongOrNull() else null
            return JsonNumber(asLong, lexeme.toDouble())
        }

        private fun digits() {
            val begin = i
            while (i < s.length && s[i] in '0'..'9') i++
            if (i == begin) fail("digits expected")
        }
    }
}
