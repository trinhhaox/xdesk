package vn.xox.xdesk.wire

import vn.xox.xdesk.wire.json.JsonBool
import vn.xox.xdesk.wire.json.JsonNumber
import vn.xox.xdesk.wire.json.JsonString
import vn.xox.xdesk.wire.json.JsonValue

/** Ánh xạ từng message <-> các trường JSON riêng (ngoài `t`, `id`). */
internal object ControlMessageFields {
    private fun num(v: Long) = JsonNumber.of(v)
    private fun num(v: Int) = JsonNumber.of(v.toLong())
    private fun str(v: String) = JsonString(v)

    fun write(m: ControlMessage, f: MutableMap<String, JsonValue>) {
        when (m) {
            is ControlMessage.Hello -> { f["ver"] = str(m.ver); f["caps"] = num(m.caps); f["name"] = str(m.name) }
            is ControlMessage.Welcome -> { f["ver"] = str(m.ver); f["sessionId"] = str(m.sessionId); f["caps"] = num(m.caps) }
            is ControlMessage.Reject -> { f["reason"] = str(m.reason); m.detail?.let { f["detail"] = str(it) } }
            is ControlMessage.DisplayConfig -> {
                f["w"] = num(m.w); f["h"] = num(m.h); f["scale"] = JsonNumber.of(m.scale); f["fps"] = num(m.fps)
                f["codec"] = str(m.codec.wire); m.mode?.let { f["mode"] = str(it.wire) }
            }
            is ControlMessage.DisplayReady -> { f["udpPort"] = num(m.udpPort); f["streamId"] = num(m.streamId) }
            is ControlMessage.KeyframeRequest -> f["streamId"] = num(m.streamId)
            is ControlMessage.NetReport -> {
                f["rttMs"] = num(m.rttMs); f["lossPermille"] = num(m.lossPermille)
                f["jitterMs"] = num(m.jitterMs); f["recvKbps"] = num(m.recvKbps)
            }
            is ControlMessage.BitrateSet -> f["kbps"] = num(m.kbps)
            is ControlMessage.ClipOffer -> { f["kind"] = str(m.kind.wire); f["size"] = num(m.size) }
            is ControlMessage.ClipPull -> f["kind"] = str(m.kind.wire)
            is ControlMessage.ControlState -> f["owner"] = str(m.owner.wire)
            is ControlMessage.Ping -> f["t0"] = num(m.t0)
            is ControlMessage.Pong -> { f["t0"] = num(m.t0); f["t1"] = num(m.t1); f["t2"] = num(m.t2) }
            is ControlMessage.Bye -> m.reason?.let { f["reason"] = str(it) }
            is ControlMessage.InputText -> f["text"] = str(m.text)
            ControlMessage.Rekey -> Unit
            is ControlMessage.RekeyResync -> { f["epoch"] = num(m.epoch); f["ask"] = JsonBool(m.ask) }
            is ControlMessage.PairResult -> f["accepted"] = JsonBool(m.accepted)
            is ControlMessage.Unknown -> Unit
        }
    }

    fun read(type: String, r: FieldReader): ControlMessage = when (type) {
        "hello" -> ControlMessage.Hello(r.string("ver"), r.u32("caps"), r.string("name"))
        "welcome" -> ControlMessage.Welcome(r.string("ver"), r.string("sessionId"), r.u32("caps"))
        "reject" -> ControlMessage.Reject(r.string("reason"), r.optString("detail"))
        "display.config" -> ControlMessage.DisplayConfig(
            r.u32("w"), r.u32("h"), r.double("scale"), r.u32("fps"),
            r.enum("codec", VideoCodec.entries.toTypedArray()) { it.wire },
            r.optEnum("mode", ScreenMode.entries.toTypedArray()) { it.wire },
        )
        "display.ready" -> ControlMessage.DisplayReady(r.u16("udpPort"), r.u16("streamId"))
        "keyframe.request" -> ControlMessage.KeyframeRequest(r.u16("streamId"))
        "net.report" -> ControlMessage.NetReport(r.u32("rttMs"), r.u32("lossPermille"), r.u32("jitterMs"), r.u32("recvKbps"))
        "bitrate.set" -> ControlMessage.BitrateSet(r.u32("kbps"))
        "clip.offer" -> ControlMessage.ClipOffer(r.enum("kind", ClipKind.entries.toTypedArray()) { it.wire }, r.u32("size"))
        "clip.pull" -> ControlMessage.ClipPull(r.enum("kind", ClipKind.entries.toTypedArray()) { it.wire })
        "control.state" -> ControlMessage.ControlState(r.enum("owner", ControlOwner.entries.toTypedArray()) { it.wire })
        "ping" -> ControlMessage.Ping(r.i64("t0"))
        "pong" -> ControlMessage.Pong(r.i64("t0"), r.i64("t1"), r.i64("t2"))
        "bye" -> ControlMessage.Bye(r.optString("reason"))
        "input.text" -> ControlMessage.InputText(r.string("text"))
        "rekey" -> ControlMessage.Rekey
        "rekey.resync" -> ControlMessage.RekeyResync(r.u32("epoch"), r.bool("ask"))
        "pair.result" -> ControlMessage.PairResult(r.bool("accepted"))
        else -> ControlMessage.Unknown(type)
    }
}
