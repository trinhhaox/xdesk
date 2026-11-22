package vn.xox.xdesk.wire

import vn.xox.xdesk.wire.json.JsonArray
import vn.xox.xdesk.wire.json.JsonBool
import vn.xox.xdesk.wire.json.JsonNumber
import vn.xox.xdesk.wire.json.JsonObject
import vn.xox.xdesk.wire.json.JsonString
import vn.xox.xdesk.wire.json.JsonValue

/** Ánh xạ từng message <-> các trường JSON riêng (ngoài `t`, `id`). */
internal object ControlMessageFields {
    private fun num(v: Long) = JsonNumber.of(v)
    private fun num(v: Int) = JsonNumber.of(v.toLong())
    private fun str(v: String) = JsonString(v)

    private fun writeDisplayConfig(m: ControlMessage.DisplayConfig, f: MutableMap<String, JsonValue>) {
        f["w"] = num(m.w); f["h"] = num(m.h); f["scale"] = JsonNumber.of(m.scale); f["fps"] = num(m.fps)
        f["codec"] = str(m.codec.wire); m.mode?.let { f["mode"] = str(it.wire) }
        m.mirrorFit?.let { f["mirrorFit"] = str(it.wire) }
        m.videoPaused?.let { f["videoPaused"] = JsonBool(it) }
        m.displayId?.let { f["displayId"] = num(it) }
    }

    private fun readDisplayConfig(r: FieldReader) = ControlMessage.DisplayConfig(
        r.u32("w"), r.u32("h"), r.double("scale"), r.u32("fps"),
        r.enum("codec", VideoCodec.entries.toTypedArray()) { it.wire },
        r.optEnum("mode", ScreenMode.entries.toTypedArray()) { it.wire },
        r.optEnum("mirrorFit", MirrorFit.entries.toTypedArray()) { it.wire },
        r.optBool("videoPaused"),
        r.optU32("displayId"),
    )

    fun write(m: ControlMessage, f: MutableMap<String, JsonValue>) {
        when (m) {
            is ControlMessage.Hello -> { f["ver"] = str(m.ver); f["caps"] = num(m.caps); f["name"] = str(m.name) }
            is ControlMessage.Welcome -> { f["ver"] = str(m.ver); f["sessionId"] = str(m.sessionId); f["caps"] = num(m.caps) }
            is ControlMessage.Reject -> { f["reason"] = str(m.reason); m.detail?.let { f["detail"] = str(it) } }
            is ControlMessage.DisplayConfig -> writeDisplayConfig(m, f)
            is ControlMessage.DisplayReconfigure -> writeDisplayConfig(m.config, f)
            is ControlMessage.DisplayReady -> { f["udpPort"] = num(m.udpPort); f["streamId"] = num(m.streamId) }
            is ControlMessage.KeyframeRequest -> f["streamId"] = num(m.streamId)
            is ControlMessage.VideoPause -> f["streamId"] = num(m.streamId)
            is ControlMessage.VideoResume -> f["streamId"] = num(m.streamId)
            is ControlMessage.NetReport -> {
                f["rttMs"] = num(m.rttMs); f["lossPermille"] = num(m.lossPermille)
                f["jitterMs"] = num(m.jitterMs); f["recvKbps"] = num(m.recvKbps)
            }
            is ControlMessage.BitrateSet -> f["kbps"] = num(m.kbps)
            is ControlMessage.ClipOffer -> {
                f["kind"] = str(m.kind.wire)
                f["size"] = num(m.size)
                m.hash?.let { f["hash"] = str(it) }
            }
            is ControlMessage.ClipPull -> f["kind"] = str(m.kind.wire)
            is ControlMessage.ClipData -> {
                f["kind"] = str(m.kind.wire)
                f["size"] = num(m.size)
                f["hash"] = str(m.hash)
            }
            is ControlMessage.ControlState -> f["owner"] = str(m.owner.wire)
            is ControlMessage.Ping -> f["t0"] = num(m.t0)
            is ControlMessage.Pong -> { f["t0"] = num(m.t0); f["t1"] = num(m.t1); f["t2"] = num(m.t2) }
            is ControlMessage.Bye -> m.reason?.let { f["reason"] = str(it) }
            is ControlMessage.InputText -> f["text"] = str(m.text)
            ControlMessage.Rekey -> Unit
            is ControlMessage.RekeyResync -> { f["epoch"] = num(m.epoch); f["ask"] = JsonBool(m.ask) }
            is ControlMessage.PairResult -> f["accepted"] = JsonBool(m.accepted)
            is ControlMessage.AgentApprove -> {
                f["requestId"] = str(m.requestId)
                m.agentName?.let { f["agentName"] = str(it) }
                m.summary?.let { f["summary"] = str(it) }
                m.expiresAt?.let { f["expiresAt"] = num(it) }
                m.allow?.let { f["allow"] = JsonBool(it) }
            }
            ControlMessage.SystemLock -> Unit
            is ControlMessage.SystemLockResult -> { f["ok"] = JsonBool(m.ok); f["message"] = str(m.message) }
            is ControlMessage.HostState -> { f["videoAvailable"] = JsonBool(m.videoAvailable); f["locked"] = JsonBool(m.locked) }
            is ControlMessage.SystemUnlock -> {
                m.token?.let { f["token"] = str(it) }
                m.sig?.let { f["sig"] = str(it) }
            }
            is ControlMessage.SystemUnlockChallenge -> { f["nonce"] = str(m.nonce); f["ttlMs"] = num(m.ttlMs) }
            is ControlMessage.UnlockKey -> { f["alg"] = str(m.alg); f["pub"] = str(m.pub) }
            is ControlMessage.SystemUnlockResult -> {
                f["ok"] = JsonBool(m.ok)
                f["message"] = str(m.message)
            }
            is ControlMessage.MediaKey -> f["key"] = str(m.key.wire)
            is ControlMessage.DisplayList -> f["displays"] = JsonArray(
                m.displays.map { d ->
                    JsonObject(
                        linkedMapOf(
                            "id" to num(d.id),
                            "name" to str(d.name),
                            "width" to num(d.width),
                            "height" to num(d.height),
                            "isMain" to JsonBool(d.isMain),
                        ),
                    )
                },
            )
            is ControlMessage.FileOffer -> {
                f["name"] = str(m.name)
                f["size"] = num(m.size)
                f["hash"] = str(m.hash)
            }
            is ControlMessage.FileData -> {
                f["name"] = str(m.name)
                f["chunk"] = str(m.chunk)
                f["isLast"] = JsonBool(m.isLast)
            }
            is ControlMessage.FileStart -> {
                f["transferId"] = str(m.id)
                f["name"] = str(m.name)
                f["size"] = num(m.size)
            }
            is ControlMessage.FileChunk -> {
                f["transferId"] = str(m.id)
                f["size"] = num(m.size)
            }
            is ControlMessage.FileDone -> {
                f["transferId"] = str(m.id)
                f["hash"] = str(m.hash)
            }
            is ControlMessage.FileCancel -> {
                f["transferId"] = str(m.id)
                m.reason?.let { f["reason"] = str(it) }
            }
            is ControlMessage.AgentHelp -> {
                f["requestId"] = str(m.requestId)
                m.reason?.let { f["reason"] = str(it) }
                m.resolved?.let { f["resolved"] = JsonBool(it) }
            }
            is ControlMessage.WindowPick, is ControlMessage.WindowSelected, is ControlMessage.WindowAdjust ->
                ControlWindowFields.write(m, f)
            is ControlMessage.Unknown -> Unit
        }
    }

    fun read(type: String, r: FieldReader): ControlMessage = when (type) {
        "hello" -> ControlMessage.Hello(r.string("ver"), r.u32("caps"), r.string("name"))
        "welcome" -> ControlMessage.Welcome(r.string("ver"), r.string("sessionId"), r.u32("caps"))
        "reject" -> ControlMessage.Reject(r.string("reason"), r.optString("detail"))
        "display.config" -> readDisplayConfig(r)
        "display.reconfigure" -> ControlMessage.DisplayReconfigure(readDisplayConfig(r))
        "display.ready" -> ControlMessage.DisplayReady(r.u16("udpPort"), r.u16("streamId"))
        "keyframe.request" -> ControlMessage.KeyframeRequest(r.u16("streamId"))
        "video.pause" -> ControlMessage.VideoPause(r.u16("streamId"))
        "video.resume" -> ControlMessage.VideoResume(r.u16("streamId"))
        "net.report" -> ControlMessage.NetReport(r.u32("rttMs"), r.u32("lossPermille"), r.u32("jitterMs"), r.u32("recvKbps"))
        "bitrate.set" -> ControlMessage.BitrateSet(r.u32("kbps"))
        "clip.offer" -> ControlMessage.ClipOffer(
            r.enum("kind", ClipKind.entries.toTypedArray()) { it.wire }, r.u32("size"), r.optString("hash"),
        )
        "clip.pull" -> ControlMessage.ClipPull(r.enum("kind", ClipKind.entries.toTypedArray()) { it.wire })
        "clip.data" -> ControlMessage.ClipData(
            r.enum("kind", ClipKind.entries.toTypedArray()) { it.wire }, r.u32("size"), r.string("hash"),
        )
        "control.state" -> ControlMessage.ControlState(r.enum("owner", ControlOwner.entries.toTypedArray()) { it.wire })
        "ping" -> ControlMessage.Ping(r.i64("t0"))
        "pong" -> ControlMessage.Pong(r.i64("t0"), r.i64("t1"), r.i64("t2"))
        "bye" -> ControlMessage.Bye(r.optString("reason"))
        "input.text" -> ControlMessage.InputText(r.string("text"))
        "rekey" -> ControlMessage.Rekey
        "rekey.resync" -> ControlMessage.RekeyResync(r.u32("epoch"), r.bool("ask"))
        "pair.result" -> ControlMessage.PairResult(r.bool("accepted"))
        "agent.approve" -> ControlMessage.AgentApprove(
            r.string("requestId"), r.optString("agentName"), r.optString("summary"), r.optI64("expiresAt"), r.optBool("allow"),
        )
        "system.lock" -> ControlMessage.SystemLock
        "system.lock.result" -> ControlMessage.SystemLockResult(r.bool("ok"), r.string("message"))
        "host.state" -> ControlMessage.HostState(r.bool("videoAvailable"), r.bool("locked"))
        "system.unlock" -> ControlMessage.SystemUnlock(r.optString("token"), r.optString("sig"))
        "system.unlock.challenge" -> ControlMessage.SystemUnlockChallenge(r.string("nonce"), r.u32("ttlMs"))
        "unlock.key" -> ControlMessage.UnlockKey(r.string("alg"), r.string("pub"))
        "system.unlock.result" -> ControlMessage.SystemUnlockResult(r.bool("ok"), r.string("message"))
        "media.key" -> ControlMessage.MediaKey(r.enum("key", MediaKeyKind.entries.toTypedArray()) { it.wire })
        "display.list" -> ControlMessage.DisplayList(
            r.array("displays").map { elem ->
                val obj = elem as? JsonObject ?: wireError(WireErrorCode.malformedJSON, "field displays")
                val itemReader = FieldReader(obj)
                DisplayInfo(
                    itemReader.u32("id"),
                    itemReader.string("name"),
                    itemReader.u32("width"),
                    itemReader.u32("height"),
                    itemReader.bool("isMain"),
                )
            },
        )
        "file.offer" -> ControlMessage.FileOffer(
            r.string("name"), r.i64("size"), r.string("hash"),
        )
        "file.data" -> ControlMessage.FileData(
            r.string("name"), r.string("chunk"), r.bool("isLast"),
        )
        "file.start" -> ControlMessage.FileStart(r.string("transferId"), r.string("name"), r.i64("size"))
        "file.chunk" -> ControlMessage.FileChunk(r.string("transferId"), r.u32("size"))
        "file.done" -> ControlMessage.FileDone(r.string("transferId"), r.string("hash"))
        "file.cancel" -> ControlMessage.FileCancel(r.string("transferId"), r.optString("reason"))
        "agent.help" -> ControlMessage.AgentHelp(
            r.string("requestId"), r.optString("reason"), r.optBool("resolved"),
        )
        "window.pick", "window.selected", "window.adjust" -> ControlWindowFields.read(type, r)
        else -> ControlMessage.Unknown(type)
    }
}
