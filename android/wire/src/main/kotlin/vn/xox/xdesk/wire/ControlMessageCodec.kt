package vn.xox.xdesk.wire

import vn.xox.xdesk.wire.json.JsonBool
import vn.xox.xdesk.wire.json.JsonNull
import vn.xox.xdesk.wire.json.JsonNumber
import vn.xox.xdesk.wire.json.JsonObject
import vn.xox.xdesk.wire.json.JsonParser
import vn.xox.xdesk.wire.json.JsonString
import vn.xox.xdesk.wire.json.JsonSyntaxException
import vn.xox.xdesk.wire.json.JsonValue
import vn.xox.xdesk.wire.json.JsonWriter

/** JSON phẳng `{"id":1,"t":"ping","t0":123}`; đầu ra dạng chuẩn (khoá sắp xếp). */
object ControlMessageCodec {
    fun encode(envelope: ControlEnvelope): ByteArray {
        val message = envelope.message
        message.validate()
        if (envelope.id !in 0..U32_MAX) wireError(WireErrorCode.invalidField, "id")
        val fields = LinkedHashMap<String, JsonValue>()
        fields["id"] = JsonNumber.of(envelope.id)
        fields["t"] = JsonString(typeName(message))
        ControlMessageFields.write(message, fields)
        return JsonWriter.write(JsonObject(fields))
    }

    fun decode(bytes: ByteArray): ControlEnvelope {
        val root = try {
            JsonParser.parse(bytes) as? JsonObject
        } catch (e: JsonSyntaxException) {
            wireError(WireErrorCode.malformedJSON, e.message.orEmpty())
        } ?: wireError(WireErrorCode.malformedJSON, "not an object")
        val reader = FieldReader(root)
        val type = reader.string("t")
        val id = reader.u32("id")
        val message = ControlMessageFields.read(type, reader)
        message.validate()
        return ControlEnvelope(id, message)
    }

    private const val U32_MAX = 0xFFFFFFFFL

    fun typeName(message: ControlMessage): String = when (message) {
        is ControlMessage.Hello -> "hello"
        is ControlMessage.Welcome -> "welcome"
        is ControlMessage.Reject -> "reject"
        is ControlMessage.DisplayConfig -> "display.config"
        is ControlMessage.DisplayReady -> "display.ready"
        is ControlMessage.KeyframeRequest -> "keyframe.request"
        is ControlMessage.NetReport -> "net.report"
        is ControlMessage.BitrateSet -> "bitrate.set"
        is ControlMessage.ClipOffer -> "clip.offer"
        is ControlMessage.ClipPull -> "clip.pull"
        is ControlMessage.ControlState -> "control.state"
        is ControlMessage.Ping -> "ping"
        is ControlMessage.Pong -> "pong"
        is ControlMessage.Bye -> "bye"
        is ControlMessage.InputText -> "input.text"
        ControlMessage.Rekey -> "rekey"
        is ControlMessage.RekeyResync -> "rekey.resync"
        is ControlMessage.PairResult -> "pair.result"
        is ControlMessage.AgentApprove -> "agent.approve"
        ControlMessage.SystemLock -> "system.lock"
        is ControlMessage.SystemUnlock -> "system.unlock"
        is ControlMessage.FileOffer -> "file.offer"
        is ControlMessage.FileData -> "file.data"
        is ControlMessage.AgentHelp -> "agent.help"
        is ControlMessage.Unknown -> message.type
    }
}

/** Đọc trường có kiểu từ object JSON; thiếu/sai kiểu/ngoài miền → `malformedJSON`. */
internal class FieldReader(private val obj: JsonObject) {
    private fun bad(key: String): Nothing = wireError(WireErrorCode.malformedJSON, "field $key")

    fun string(key: String): String = (obj[key] as? JsonString)?.value ?: bad(key)

    fun optString(key: String): String? = when (val v = obj[key]) {
        null, JsonNull -> null
        is JsonString -> v.value
        else -> bad(key)
    }

    fun bool(key: String): Boolean = (obj[key] as? JsonBool)?.value ?: bad(key)

    fun optBool(key: String): Boolean? = when (val v = obj[key]) {
        null, JsonNull -> null
        is JsonBool -> v.value
        else -> bad(key)
    }

    fun optI64(key: String): Long? = if (obj[key] == null || obj[key] == JsonNull) null else i64(key)

    fun double(key: String): Double = (obj[key] as? JsonNumber)?.double ?: bad(key)

    fun i64(key: String): Long = (obj[key] as? JsonNumber)?.exactLong() ?: bad(key)

    fun u32(key: String): Long = i64(key).takeIf { it in 0..0xFFFFFFFFL } ?: bad(key)

    fun u16(key: String): Int = i64(key).takeIf { it in 0..0xFFFF }?.toInt() ?: bad(key)

    fun <E : Enum<E>> enum(key: String, values: Array<E>, wire: (E) -> String): E {
        val text = string(key)
        return values.firstOrNull { wire(it) == text } ?: bad(key)
    }

    fun <E : Enum<E>> optEnum(key: String, values: Array<E>, wire: (E) -> String): E? =
        if (obj[key] == null || obj[key] == JsonNull) null else enum(key, values, wire)
}
