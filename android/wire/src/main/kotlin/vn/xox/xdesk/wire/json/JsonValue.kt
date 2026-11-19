package vn.xox.xdesk.wire.json

/** Giá trị JSON tối thiểu cho message điều khiển (phẳng, nhưng parser vẫn chấp nhận lồng có giới hạn độ sâu). */
sealed interface JsonValue

data object JsonNull : JsonValue

data class JsonBool(val value: Boolean) : JsonValue

data class JsonString(val value: String) : JsonValue

/** Số: `long` có giá trị khi lexeme là số nguyên vừa Long; `double` luôn có. */
data class JsonNumber(val long: Long?, val double: Double) : JsonValue {
    /** Số nguyên chính xác, hoặc số thực nguyên (vd `2.0`); ngoài ra `null`. */
    fun exactLong(): Long? {
        long?.let { return it }
        return if (double.isFinite() && double == Math.rint(double) && Math.abs(double) < MAX_EXACT) double.toLong() else null
    }

    companion object {
        private const val MAX_EXACT = 9.007199254740992E15
        fun of(value: Long) = JsonNumber(value, value.toDouble())
        fun of(value: Double) = JsonNumber(null, value)
    }
}

data class JsonArray(val items: List<JsonValue>) : JsonValue

data class JsonObject(val fields: Map<String, JsonValue>) : JsonValue {
    operator fun get(key: String): JsonValue? = fields[key]
}
