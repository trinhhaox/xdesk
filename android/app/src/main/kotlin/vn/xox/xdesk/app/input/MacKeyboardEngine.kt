package vn.xox.xdesk.app.input

import vn.xox.xdesk.transport.InputEvents
import vn.xox.xdesk.transport.InputModifiers
import vn.xox.xdesk.wire.InputEvent

/** Ảnh chụp bất biến để vẽ giao diện (Compose state). */
data class MacKeyboardSnapshot(
    val modifiers: Map<Int, MacKeyboardEngine.ModState> = emptyMap(),
    val pressed: Set<Int> = emptySet(),
    val capsLock: Boolean = false,
) {
    fun modState(usage: Int): MacKeyboardEngine.ModState = modifiers[usage] ?: MacKeyboardEngine.ModState.OFF
    val shiftActive: Boolean get() = modifiers.any { (usage, s) -> MacKeyLayout.modifierBit(usage) == InputModifiers.SHIFT && s != MacKeyboardEngine.ModState.OFF }
}

/** Caps Lock sống hoàn toàn trên điện thoại (không gửi HID 0x39); giữ ngoài panel để sống sót qua việc dựng lại giao diện trong một phiên. */
class CapsLockState {
    var on = false
}

/**
 * Máy trạng thái bàn phím Mac: biến chạm xuống/nhả từng phím thành `key down/up` HID thật (phím vật lý, không gửi văn bản).
 * Bổ trợ: chạm = dính một lần (áp cho phím kế rồi nhả), chạm đôi trong [DOUBLE_TAP_MS] = khoá, giữ + bấm phím khác bằng ngón khác = chord.
 * Chỉ dùng trên một luồng (UI). Mỗi thao tác trả danh sách sự kiện cần gửi theo thứ tự.
 */
class MacKeyboardEngine(private val caps: CapsLockState = CapsLockState(), private val repeater: KeyRepeater = KeyRepeater()) {
    enum class ModState { OFF, ARMED, LOCKED }

    private class Mod {
        var state = ModState.OFF
        var pressed = false
        var chorded = false
        var wasArmedOnDown = false
        var downMs = 0L
        var lastTapMs = Long.MIN_VALUE / 2
    }

    private val mods = HashMap<Int, Mod>()
    private val heldKeys = LinkedHashSet<Int>()
    /** Phím thường đang đè → các bổ trợ dính nó đã dùng (nhả khi phím nhả). */
    private val consumed = HashMap<Int, ConsumedMods>()

    private class ConsumedMods(val usages: List<Int>, val mods: Int)

    private fun mod(usage: Int) = mods.getOrPut(usage) { Mod() }

    /** Bit `mods` của mọi phím bổ trợ đang đè xuống trên Mac. */
    val activeMods: Int get() = mods.entries.fold(if (caps.on) InputModifiers.CAPS_LOCK else 0) { acc, (usage, m) ->
        if (m.state != ModState.OFF) acc or MacKeyLayout.modifierBit(usage) else acc
    }

    fun snapshot() = MacKeyboardSnapshot(
        modifiers = mods.filterValues { it.state != ModState.OFF }.mapValues { it.value.state },
        pressed = heldKeys.toSet(),
        capsLock = caps.on,
    )

    /** Chạm xuống: tắt → dính (gửi down); dính + chạm lần hai trong [DOUBLE_TAP_MS] → khoá; còn lại → nhả. */
    fun modifierDown(usage: Int, nowMs: Long): List<InputEvent> {
        val m = mod(usage)
        m.pressed = true
        m.chorded = false
        m.downMs = nowMs
        m.wasArmedOnDown = false
        return when (m.state) {
            ModState.OFF -> {
                m.state = ModState.ARMED
                m.lastTapMs = nowMs
                listOf(InputEvents.key(usage, true, activeMods))
            }
            ModState.ARMED -> if (nowMs - m.lastTapMs <= DOUBLE_TAP_MS) {
                m.state = ModState.LOCKED
                m.lastTapMs = Long.MIN_VALUE / 2
                emptyList()
            } else {
                m.wasArmedOnDown = true
                m.lastTapMs = nowMs
                emptyList()
            }
            ModState.LOCKED -> release(usage, m)
        }
    }

    /** Nhấc tay: bổ trợ dính đã tạo tổ hợp, giữ lâu hơn [HOLD_MS], hoặc chạm nhanh lên bổ trợ đang dính (huỷ) thì nhả. */
    fun modifierUp(usage: Int, nowMs: Long): List<InputEvent> {
        val m = mod(usage)
        m.pressed = false
        if (m.state != ModState.ARMED || !(m.chorded || m.wasArmedOnDown || nowMs - m.downMs > HOLD_MS)) return emptyList()
        return release(usage, m)
    }

    /** Phím thường: bổ trợ dính chưa bị ngón nào giữ được dùng ngay lúc xuống (tắt luôn), nhả HID khi phím này nhả. Caps Lock chỉ đổi trạng thái cục bộ. */
    fun keyDown(usage: Int, nowMs: Long): List<InputEvent> {
        if (!heldKeys.add(usage)) return emptyList()
        if (usage == MacKeyLayout.CAPS_LOCK) {
            caps.on = !caps.on
            return emptyList()
        }
        mods.values.forEach { if (it.pressed) it.chorded = true }
        val current = activeMods
        val used = mods.entries.filter { it.value.state == ModState.ARMED && !it.value.pressed }.map { it.key }.sorted()
        used.forEach { mods.getValue(it).state = ModState.OFF }
        consumed[usage] = ConsumedMods(used, current)
        repeater.keyDown(usage, current, nowMs)
        return listOf(InputEvents.key(usage, true, current))
    }

    fun keyUp(usage: Int): List<InputEvent> {
        if (!heldKeys.remove(usage)) return emptyList()
        val used = consumed.remove(usage) ?: return emptyList()
        repeater.keyUp(usage)
        val events = mutableListOf(InputEvents.key(usage, false, used.mods))
        used.usages.filter { mods.getValue(it).state == ModState.OFF }.forEach { events += InputEvents.key(it, false, activeMods) }
        return events
    }

    /** Lặp phím giữ; gọi định kỳ. */
    fun tick(nowMs: Long): List<InputEvent> = repeater.tick(nowMs)

    /** Nhả mọi phím và bổ trợ (rời chế độ, ra nền, ngắt kết nối). Caps Lock (trạng thái phiên) giữ nguyên. */
    fun releaseAll(): List<InputEvent> {
        repeater.releaseAll()
        val events = mutableListOf<InputEvent>()
        consumed.forEach { (usage, c) -> events += InputEvents.key(usage, false, c.mods) }
        consumed.values.flatMap { it.usages }.toSet().forEach { u -> if (mods.getValue(u).state == ModState.OFF) events += InputEvents.key(u, false, 0) }
        consumed.clear()
        heldKeys.clear()
        mods.values.forEach { it.pressed = false }
        mods.entries.filter { it.value.state != ModState.OFF }.forEach { (u, m) -> events += release(u, m) }
        return events
    }

    private fun release(usage: Int, m: Mod): List<InputEvent> {
        m.state = ModState.OFF
        return listOf(InputEvents.key(usage, false, activeMods))
    }

    companion object {
        const val DOUBLE_TAP_MS = 400L
        const val HOLD_MS = 350L
    }
}
