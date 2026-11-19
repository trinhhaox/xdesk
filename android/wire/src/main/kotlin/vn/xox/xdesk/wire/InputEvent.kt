package vn.xox.xdesk.wire

enum class InputKind(val raw: Int) {
    MOVE(0), DOWN(1), UP(2), SCROLL(3), KEY(4), TEXT_REF(5), TOUCH(6);

    companion object {
        fun of(raw: Int): InputKind? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * Sự kiện input cố định 28 byte:
 * `u8 kind | u8 button | u16 mods | u32 seq | f32 x | f32 y | f32 dx | f32 dy | u16 keyUsage | u16 pad`.
 */
data class InputEvent(
    val kind: InputKind,
    val button: Int = 0,
    val mods: Int = 0,
    val seq: Long,
    val x: Float = 0f,
    val y: Float = 0f,
    val dx: Float = 0f,
    val dy: Float = 0f,
    val keyUsage: Int = 0,
) {
    private val isPointer: Boolean
        get() = kind == InputKind.MOVE || kind == InputKind.DOWN || kind == InputKind.UP || kind == InputKind.TOUCH

    private fun validate() {
        if (!(x.isFinite() && y.isFinite() && dx.isFinite() && dy.isFinite())) wireError(WireErrorCode.invalidInput, "non-finite float")
        if (isPointer && !(x >= 0f && x <= 1f && y >= 0f && y <= 1f)) wireError(WireErrorCode.invalidInput, "coordinate out of 0...1")
    }

    private fun write(w: ByteWriter) {
        validate()
        w.u8(kind.raw); w.u8(button); w.u16(mods); w.u32(seq)
        w.f32(x); w.f32(y); w.f32(dx); w.f32(dy)
        w.u16(keyUsage); w.u16(0)
    }

    companion object {
        const val SIZE = 28
        const val MAX_BATCH = MediaPacket.MAX_PAYLOAD / SIZE

        private fun read(r: ByteReader): InputEvent {
            val rawKind = r.u8()
            val kind = InputKind.of(rawKind) ?: wireError(WireErrorCode.invalidInput, "unknown kind $rawKind")
            val button = r.u8()
            val mods = r.u16()
            val seq = r.u32()
            val x = r.f32(); val y = r.f32(); val dx = r.f32(); val dy = r.f32()
            val keyUsage = r.u16()
            r.u16() // pad: bỏ qua khi đọc để chừa chỗ mở rộng
            return InputEvent(kind, button, mods, seq, x, y, dx, dy, keyUsage).also { it.validate() }
        }

        fun encodeBatch(events: List<InputEvent>): ByteArray {
            if (events.size !in 1..MAX_BATCH) wireError(WireErrorCode.invalidInput, "batch size ${events.size}")
            val w = ByteWriter(events.size * SIZE)
            events.forEach { it.write(w) }
            return w.toByteArray()
        }

        fun decodeBatch(payload: ByteArray): List<InputEvent> {
            if (payload.isEmpty() || payload.size % SIZE != 0 || payload.size / SIZE > MAX_BATCH) {
                wireError(WireErrorCode.invalidInput, "payload length ${payload.size}")
            }
            val r = ByteReader(payload)
            return List(payload.size / SIZE) { read(r) }
        }
    }
}

/** Payload gói input-ack: `u32 seq` lớn nhất nhận liên tục. */
data class InputAck(val seq: Long) {
    fun encode(): ByteArray = ByteWriter(SIZE).also { it.u32(seq) }.toByteArray()

    companion object {
        const val SIZE = 4

        fun decode(payload: ByteArray): InputAck {
            if (payload.size != SIZE) wireError(WireErrorCode.invalidInput, "ack length ${payload.size}")
            return InputAck(ByteReader(payload).u32())
        }
    }
}
