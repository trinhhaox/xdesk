package vn.xox.xdesk.app.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.os.SystemClock
import android.view.MotionEvent
import android.widget.FrameLayout
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import vn.xox.xdesk.app.StreamInputRouter
import vn.xox.xdesk.app.input.TouchPhase
import vn.xox.xdesk.app.input.TouchSample
import vn.xox.xdesk.app.input.VideoContentMapper
import vn.xox.xdesk.app.input.VideoPan
import vn.xox.xdesk.app.input.VideoViewport

/**
 * Khung chứa video: phủ kín vùng hiển thị, đặt [surfaceView] ở hình chữ nhật aspect-fit (letterbox) của video rồi zoom/kéo bằng
 * transform của view. Mọi chạm đi qua đây (không qua SurfaceView) nên chạm vào dải đen vẫn là của trackpad, và việc đổi toạ độ dùng
 * đúng khung đã vẽ. Nút nổi là phần tử Compose nằm TRÊN khung này nên luôn nhận chạm trước.
 */
class StreamViewport(context: Context) : FrameLayout(context) {
    val surfaceView = StreamSurfaceView(context)
    var router: StreamInputRouter? = null
        set(value) { field = value; surfaceView.router = value }

    /** Cỡ video (px); null = chưa biết, video lấp đầy khung. */
    var videoSize: Pair<Int, Int>? = null
        set(value) { if (field != value) { field = value; requestLayout() } }

    /** Giống màn hình Mac: cho zoom/kéo. Tắt thì về vừa khung. */
    var zoomEnabled = false
        set(value) { field = value; if (!value) resetZoom() }

    var viewport by mutableStateOf(VideoViewport.IDENTITY)
        private set

    /** Video đang dịch lên bấy nhiêu px (bàn phím mở); cộng vào y của ngón để ra toạ độ video. */
    var panY = 0f
        set(value) { if (field != value) { field = value; applyTransform() } }

    var onViewportChanged: (zoomed: Boolean) -> Unit = {}
    var onSizeChanged: (Int, Int) -> Unit = { _, _ -> }
    var onSequenceEnded: () -> Unit = {}

    private val touch = ViewportTouchHandler(this)
    private val cursorPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var cursorUntil = 0L
    private val tick = object : Runnable {
        override fun run() {
            router?.tick()
            if (cursorUntil != 0L) { if (SystemClock.uptimeMillis() > cursorUntil) cursorUntil = 0L; invalidate() }
            postDelayed(this, TICK_MS)
        }
    }

    init {
        setWillNotDraw(false)
        addView(surfaceView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    }

    /** Khung video trong view (chưa zoom); null khi chưa biết cỡ view hoặc video. */
    val mapper: VideoContentMapper? get() = fitMapper()

    private fun fitMapper(): VideoContentMapper? {
        val (vw, vh) = videoSize ?: (width to height)
        return VideoContentMapper.of(width.toFloat(), height.toFloat(), vw.toFloat(), vh.toFloat())
    }

    override fun onAttachedToWindow() { super.onAttachedToWindow(); post(tick) }

    override fun onDetachedFromWindow() { removeCallbacks(tick); super.onDetachedFromWindow() }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val m = fitMapper()
        if (m == null) surfaceView.layout(0, 0, r - l, b - t)
        else surfaceView.layout(m.originX.toInt(), m.originY.toInt(), (m.originX + m.width).toInt(), (m.originY + m.height).toInt())
        if (changed) { onSizeChanged(r - l, b - t); fitMapper()?.let { setViewport(viewport.clamped(it)) } }
        applyTransform()
    }

    override fun onInterceptTouchEvent(ev: MotionEvent) = true

    override fun onTouchEvent(event: MotionEvent): Boolean = touch.onTouch(event)

    fun resetZoom() = setViewport(VideoViewport.IDENTITY)

    internal fun setViewport(next: VideoViewport) {
        if (next == viewport) return
        viewport = next
        applyTransform()
        onViewportChanged(!next.isIdentity)
    }

    private fun applyTransform() {
        surfaceView.pivotX = surfaceView.width / 2f
        surfaceView.pivotY = surfaceView.height / 2f
        surfaceView.scaleX = viewport.zoom
        surfaceView.scaleY = viewport.zoom
        surfaceView.translationX = viewport.translationX
        surfaceView.translationY = viewport.translationY - panY
        invalidate()
    }

    /** Toạ độ ngón (view) → mẫu chạm chuẩn hoá trên video; null nếu chạm bắt đầu ngoài khung video (dải đen ở chế độ trực tiếp). */
    internal fun sample(id: Int, x: Float, y: Float, phase: TouchPhase, now: Long, accepted: Set<Int>): TouchSample? {
        val m = mapper ?: return null
        if (phase != TouchPhase.BEGAN && id !in accepted) return null
        val vy = y + panY
        val point = if (router?.isTrackpad == true) {
            val (bx, by) = viewport.toBaseIgnoringPan(x, vy, m)
            m.normalizeUnbounded(bx, by)
        } else {
            val (bx, by) = viewport.toBase(x, vy, m)
            m.normalize(bx, by, clamping = phase != TouchPhase.BEGAN)
        }
        return point?.let { TouchSample(id, it.first, it.second, phase, now) }
    }

    /** Sau mỗi lần gửi chạm: hiện con trỏ trackpad, và đang zoom thì kéo video theo để con trỏ không chạy ra khỏi khung nhìn. */
    internal fun afterForward() {
        if (router?.isTrackpad != true) return
        val (cx, cy) = router?.cursor ?: return
        cursorUntil = SystemClock.uptimeMillis() + CURSOR_VISIBLE_MS
        val m = mapper
        if (m != null && !viewport.isIdentity) {
            setViewport(viewport.revealing(m.originX + cx * m.width, m.originY + cy * m.height, resources.displayMetrics.density * REVEAL_MARGIN_DP, m))
        }
        invalidate()
    }

    internal fun sequenceEnded() = onSequenceEnded()

    /** Độ dịch lên để vùng vừa thao tác nằm trên bàn phím (0 khi bàn phím đóng); tính theo vị trí đã zoom/kéo. */
    fun keyboardPan(obscured: Float): Float {
        val m = mapper ?: return 0f
        val focus = router?.focusY ?: return 0f
        val focusY = viewport.toView(0f, m.originY + focus * m.height, m).second
        val bottom = viewport.toView(0f, m.originY + m.height, m).second
        return VideoPan.offset(focusY, height.toFloat(), obscured, bottom)
    }

    override fun dispatchDraw(canvas: Canvas) {
        super.dispatchDraw(canvas)
        val (cx, cy) = router?.cursor ?: return
        val m = mapper
        if (m == null || cursorUntil == 0L) return
        val (x, y) = viewport.toView(m.originX + cx * m.width, m.originY + cy * m.height, m)
        val unit = resources.displayMetrics.density
        val arrow = Path().apply {
            moveTo(x, y - panY); lineTo(x, y - panY + 17 * unit); lineTo(x + 4.2f * unit, y - panY + 13.2f * unit)
            lineTo(x + 7 * unit, y - panY + 19.5f * unit); lineTo(x + 9.8f * unit, y - panY + 18.3f * unit)
            lineTo(x + 7 * unit, y - panY + 12.2f * unit); lineTo(x + 12 * unit, y - panY + 12.2f * unit); close()
        }
        cursorPaint.style = Paint.Style.FILL; cursorPaint.color = android.graphics.Color.WHITE
        canvas.drawPath(arrow, cursorPaint)
        cursorPaint.style = Paint.Style.STROKE; cursorPaint.strokeWidth = 1.2f * unit; cursorPaint.color = android.graphics.Color.BLACK
        canvas.drawPath(arrow, cursorPaint)
    }

    private companion object {
        const val TICK_MS = 50L
        const val CURSOR_VISIBLE_MS = 1500L
        const val REVEAL_MARGIN_DP = 40f
    }
}
