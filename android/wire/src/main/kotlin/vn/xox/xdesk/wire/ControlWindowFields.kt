package vn.xox.xdesk.wire

import vn.xox.xdesk.wire.json.JsonBool
import vn.xox.xdesk.wire.json.JsonNumber
import vn.xox.xdesk.wire.json.JsonObject
import vn.xox.xdesk.wire.json.JsonString
import vn.xox.xdesk.wire.json.JsonValue

/** Trường JSON và kiểm tra giá trị của `window.pick/selected/adjust` (cap `windowControl`). */
internal object ControlWindowFields {
    private fun invalid(field: String): Nothing = wireError(WireErrorCode.invalidField, field)

    fun write(m: ControlMessage, f: MutableMap<String, JsonValue>) {
        when (m) {
            is ControlMessage.WindowPick -> { f["x"] = JsonNumber.of(m.x); f["y"] = JsonNumber.of(m.y) }
            is ControlMessage.WindowSelected -> {
                f["ok"] = JsonBool(m.ok)
                m.windowId?.let { f["windowId"] = JsonNumber.of(it) }
                m.app?.let { f["app"] = JsonString(it) }
                m.title?.let { f["title"] = JsonString(it) }
                m.frame?.let { fr ->
                    f["frame"] = JsonObject(
                        linkedMapOf(
                            "x" to JsonNumber.of(fr.x), "y" to JsonNumber.of(fr.y),
                            "w" to JsonNumber.of(fr.w), "h" to JsonNumber.of(fr.h),
                        ),
                    )
                }
                m.resizable?.let { f["resizable"] = JsonBool(it) }
                m.message?.let { f["message"] = JsonString(it) }
            }
            is ControlMessage.WindowAdjust -> {
                f["windowId"] = JsonNumber.of(m.windowId)
                f["op"] = JsonString(m.op.wire)
                m.dx?.let { f["dx"] = JsonNumber.of(it) }
                m.dy?.let { f["dy"] = JsonNumber.of(it) }
                m.w?.let { f["w"] = JsonNumber.of(it) }
                m.h?.let { f["h"] = JsonNumber.of(it) }
                m.preset?.let { f["preset"] = JsonString(it.wire) }
            }
            else -> Unit
        }
    }

    fun read(type: String, r: FieldReader): ControlMessage = when (type) {
        "window.pick" -> ControlMessage.WindowPick(r.double("x"), r.double("y"))
        "window.selected" -> ControlMessage.WindowSelected(
            r.bool("ok"), r.optU32("windowId"), r.optString("app"), r.optString("title"),
            r.optObject("frame")?.let { fr -> WindowFrame(fr.double("x"), fr.double("y"), fr.double("w"), fr.double("h")) },
            r.optBool("resizable"), r.optString("message"),
        )
        else -> ControlMessage.WindowAdjust(
            r.u32("windowId"),
            r.enum("op", WindowAdjustOp.entries.toTypedArray()) { it.wire },
            r.optDouble("dx"), r.optDouble("dy"), r.optDouble("w"), r.optDouble("h"),
            r.optEnum("preset", WindowPreset.entries.toTypedArray()) { it.wire },
        )
    }

    fun validate(m: ControlMessage) {
        when (m) {
            is ControlMessage.WindowPick -> if (!m.x.isFinite() || !m.y.isFinite()) invalid("window.pick.xy")
            is ControlMessage.WindowSelected -> {
                if (m.frame != null && !m.frame.isValid) invalid("window.selected.frame")
                val tooLong = listOf(m.app, m.title, m.message).any {
                    (it?.toByteArray(Charsets.UTF_8)?.size ?: 0) > ControlMessage.WindowSelected.MAX_TEXT_BYTES
                }
                if (tooLong) invalid("window.selected.text")
            }
            is ControlMessage.WindowAdjust -> when (m.op) {
                WindowAdjustOp.MOVE -> if (m.dx?.isFinite() != true || m.dy?.isFinite() != true) invalid("window.adjust.move")
                WindowAdjustOp.RESIZE ->
                    if (m.w?.isFinite() != true || m.h?.isFinite() != true || (m.w ?: 0.0) <= 0.0 || (m.h ?: 0.0) <= 0.0) invalid("window.adjust.resize")
                WindowAdjustOp.PRESET -> if (m.preset == null) invalid("window.adjust.preset")
            }
            else -> Unit
        }
    }
}
