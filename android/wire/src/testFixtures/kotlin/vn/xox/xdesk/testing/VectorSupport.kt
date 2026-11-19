package vn.xox.xdesk.testing

import java.io.File
import vn.xox.xdesk.wire.Hex
import vn.xox.xdesk.wire.json.JsonArray
import vn.xox.xdesk.wire.json.JsonBool
import vn.xox.xdesk.wire.json.JsonNumber
import vn.xox.xdesk.wire.json.JsonObject
import vn.xox.xdesk.wire.json.JsonParser
import vn.xox.xdesk.wire.json.JsonString
import vn.xox.xdesk.wire.json.JsonValue

/** Đọc test vectors dùng chung từ `protocol/test-vectors` (đi ngược từ thư mục làm việc của Gradle). */
object Vectors {
    private val directory: File by lazy {
        generateSequence(File(System.getProperty("user.dir")).absoluteFile) { it.parentFile }
            .map { File(it, "protocol/test-vectors") }
            .firstOrNull { it.isDirectory }
            ?: error("không tìm thấy protocol/test-vectors từ ${System.getProperty("user.dir")}")
    }

    fun load(name: String): JsonObject =
        JsonParser.parse(File(directory, name).readBytes()) as JsonObject
}

private fun JsonValue?.required(key: String): JsonValue = this ?: error("thiếu khoá $key")

fun JsonObject.value(key: String): JsonValue = this[key].required(key)
fun JsonObject.str(key: String): String = (value(key) as JsonString).value
fun JsonObject.int(key: String): Int = checkNotNull((value(key) as JsonNumber).exactLong()).toInt()
fun JsonObject.long(key: String): Long = checkNotNull((value(key) as JsonNumber).exactLong())
fun JsonObject.bool(key: String): Boolean = (value(key) as JsonBool).value
fun JsonObject.hex(key: String): ByteArray = Hex.decode(str(key))
fun JsonObject.obj(key: String): JsonObject = value(key) as JsonObject
fun JsonObject.list(key: String): List<JsonObject> = (value(key) as JsonArray).items.map { it as JsonObject }
fun JsonObject.strings(key: String): List<String> = (value(key) as JsonArray).items.map { (it as JsonString).value }
