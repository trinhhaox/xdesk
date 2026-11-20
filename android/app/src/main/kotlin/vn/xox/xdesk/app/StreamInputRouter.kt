package vn.xox.xdesk.app

import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import vn.xox.xdesk.app.input.HidKeys
import vn.xox.xdesk.app.input.PointerGestures
import vn.xox.xdesk.app.input.PointerSettings
import vn.xox.xdesk.app.input.StickyModifiers
import vn.xox.xdesk.app.input.TextAction
import vn.xox.xdesk.app.input.TextInputBridge
import vn.xox.xdesk.app.input.TouchPhase
import vn.xox.xdesk.app.input.TouchSample
import vn.xox.xdesk.app.input.createPointerGestures
import vn.xox.xdesk.transport.InputEvents
import vn.xox.xdesk.transport.ViewerSession

/** Đưa cảm ứng, bàn phím ảo/cứng và phím đặc biệt tới host. Gọi từ main thread; việc gửi mạng do [ViewerSession] đẩy sang thread I/O. */
class StreamInputRouter(private val session: ViewerSession) {
    private var gestures: PointerGestures? = null
    private var hostWidth = 0f
    private var hostHeight = 0f
    private var settings = PointerSettings()
    private var lastTouchY: Float? = null
    private val text = TextInputBridge()

    /** Phím bổ trợ dính của thanh phím phụ (state Compose để thanh vẽ lại khi đổi). */
    var modifiers by mutableStateOf(StickyModifiers())
        private set

    /** Chữ Telex đang soạn dở, chỉ để xem trước; chữ chốt mới gửi host. */
    var composingPreview by mutableStateOf("")
        private set

    /** Vị trí con trỏ cục bộ (0…1) ở chế độ trackpad; `cursorStamp` tăng mỗi lần đổi để overlay biết lúc nào hiện/ẩn. */
    var cursor by mutableStateOf<Pair<Float, Float>?>(null)
        private set
    var cursorStamp by mutableLongStateOf(0L)
        private set

    /** Chiều dọc (0…1) của vùng người dùng vừa thao tác: con trỏ (trackpad) hoặc điểm chạm cuối (trực tiếp); null nếu chưa chạm. */
    var focusY by mutableStateOf<Float?>(null)
        private set

    /** Đang ở chế độ trackpad (con trỏ cục bộ): chạm chỉ cần độ dời, không cần nằm trong khung video. */
    val isTrackpad: Boolean get() = gestures?.cursor != null

    /** Đổi kích thước host (điểm) mỗi khi `display.config` đổi: ngưỡng và delta cuộn tính theo điểm host. */
    fun configure(hostWidthPoints: Float, hostHeightPoints: Float) {
        hostWidth = hostWidthPoints
        hostHeight = hostHeightPoints
        rebuildGestures()
    }

    /** Áp cài đặt con trỏ; chỉ dựng lại bộ diễn giải khi có thay đổi thật, và giữ vị trí con trỏ. */
    fun applySettings(next: PointerSettings) {
        if (next == settings) return
        settings = next
        rebuildGestures()
    }

    private fun rebuildGestures() {
        if (hostWidth <= 0f || hostHeight <= 0f) return
        gestures = createPointerGestures(settings, hostWidth, hostHeight, gestures?.cursor)
    }

    /** Nhấn giữ đủ lâu (sẵn sàng kéo thả / click phải): view rung nhẹ báo người dùng. */
    var onHoldArmed: () -> Unit = {}

    /** `displayedWidthDp`: bề ngang video đang hiện (dp, kể cả zoom) để ngưỡng chạm tính theo ngón tay; 0 = chưa biết. */
    fun onTouch(samples: List<TouchSample>, displayedWidthDp: Float = 0f) {
        val engine = gestures ?: return
        if (displayedWidthDp > 0f && samples.any { it.phase == TouchPhase.BEGAN }) {
            engine.setHostPointsPerViewPoint(hostWidth / displayedWidthDp)
        }
        session.sendInput(samples.flatMap(engine::handle))
        engine.cursor?.let { cursor = it; cursorStamp++ }
        samples.lastOrNull { it.phase == TouchPhase.BEGAN || it.phase == TouchPhase.ENDED }?.let { lastTouchY = it.y }
        if (samples.any { it.phase == TouchPhase.ENDED || it.phase == TouchPhase.CANCELLED }) focusY = engine.cursor?.second ?: lastTouchY
    }

    /** Gọi ~50 ms/lần: nhấn giữ, cuộn quán tính sau khi nhả. */
    fun tick() {
        val engine = gestures ?: return
        val wasHolding = engine.isHolding
        engine.tick(SystemClock.uptimeMillis()).takeIf { it.isNotEmpty() }?.let(session::sendInput)
        if (!wasHolding && engine.isHolding) onHoldArmed()
    }

    fun commitText(value: String) { composingPreview = ""; apply(text.commit(value)) }
    fun setComposing(value: String) { composingPreview = value; apply(text.setComposing(value)) }
    fun finishComposing() { composingPreview = ""; apply(text.finishComposing()) }
    fun deleteBefore(count: Int) { composingPreview = text.composingText; apply(text.deleteBefore(count)) }

    fun tapKey(usage: Int, mods: Int = 0) {
        session.sendInput(listOf(InputEvents.key(usage, true, mods), InputEvents.key(usage, false, mods)))
    }

    /** Phím của thanh phím phụ: áp rồi nhả bổ trợ dính armed. */
    fun tapAccessoryKey(usage: Int) = tapKey(usage, consumeModifiers())

    fun tapModifier(bit: Int) { modifiers = modifiers.tap(bit, SystemClock.uptimeMillis()) }

    private fun consumeModifiers(): Int {
        val (mods, next) = modifiers.consume()
        modifiers = next
        return mods
    }

    private fun apply(actions: List<TextAction>) {
        for (action in actions) when (action) {
            is TextAction.Insert -> insert(action.text)
            is TextAction.Backspaces -> repeat(action.count) { tapKey(HidKeys.BACKSPACE) }
        }
    }

    /** Có bổ trợ dính + một chữ gõ được bằng một phím → gửi như phím tắt (⌘ + "c" = ⌘C); còn lại gửi như văn bản. */
    private fun insert(value: String) {
        if (modifiers.active == 0) { session.sendText(value); return }
        val usage = value.singleOrNull()?.let(HidKeys::fromChar)
        val mods = consumeModifiers()
        if (usage != null) tapKey(usage, mods) else session.sendText(value)
    }
}
