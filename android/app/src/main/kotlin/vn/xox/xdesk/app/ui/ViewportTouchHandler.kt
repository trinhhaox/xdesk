package vn.xox.xdesk.app.ui

import android.os.SystemClock
import android.view.MotionEvent
import kotlin.math.hypot
import vn.xox.xdesk.app.input.TouchPhase
import vn.xox.xdesk.app.input.TouchSample

/**
 * Máy trạng thái cảm ứng của [StreamViewport]. Chạm thường → router với toạ độ đã đổi ngược qua zoom/kéo và khung video (aspect-fit).
 * Riêng Giống màn hình Mac (zoom bật): chụm hai ngón = zoom quanh tâm chụm, ba ngón = kéo, hai ngón chạm hai lần liền = về vừa khung;
 * hai ngón song song vẫn là cuộn. Khi cử chỉ thành zoom/kéo thì chạm đang gửi bị huỷ nên Mac không nhận click lạc.
 */
internal class ViewportTouchHandler(private val view: StreamViewport) {
    private enum class Mode { FORWARD, PENDING_TWO, PINCH, PAN, IGNORE }

    private var mode = Mode.FORWARD
    private val forwarded = linkedSetOf<Int>()
    private var startDistance = 0f
    private var lastDistance = 0f
    private var lastCx = 0f
    private var lastCy = 0f
    private var twoStartMs = 0L
    private var lastTwoFingerTapMs = 0L
    private val slop = view.resources.displayMetrics.density * SLOP_DP

    fun onTouch(e: MotionEvent): Boolean {
        val now = SystemClock.uptimeMillis()
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> { mode = Mode.FORWARD; forwarded.clear(); forward(e, listOf(0), TouchPhase.BEGAN, now) }
            MotionEvent.ACTION_POINTER_DOWN -> pointerDown(e, now)
            MotionEvent.ACTION_MOVE -> move(e, now)
            MotionEvent.ACTION_POINTER_UP -> pointerUp(e, now)
            MotionEvent.ACTION_UP -> up(e, now)
            MotionEvent.ACTION_CANCEL -> { cancelForwarded(now); mode = Mode.FORWARD }
            else -> return false
        }
        return true
    }

    private fun pointerDown(e: MotionEvent, now: Long) {
        val zoomable = view.zoomEnabled
        when {
            mode == Mode.IGNORE || mode == Mode.PINCH || mode == Mode.PAN -> Unit
            zoomable && e.pointerCount >= 3 -> { cancelForwarded(now); mode = Mode.PAN; track(e) }
            zoomable && e.pointerCount == 2 && !view.viewport.isIdentity -> {
                cancelForwarded(now); mode = Mode.PENDING_TWO; twoStartMs = now; startDistance = distance(e); track(e)
            }
            zoomable && e.pointerCount == 2 -> { startDistance = distance(e); track(e); forward(e, listOf(e.actionIndex), TouchPhase.BEGAN, now) }
            else -> forward(e, listOf(e.actionIndex), TouchPhase.BEGAN, now)
        }
    }

    private fun move(e: MotionEvent, now: Long) {
        when (mode) {
            Mode.PINCH -> pinch(e)
            Mode.PAN -> pan(e)
            Mode.PENDING_TWO -> pending(e, now)
            Mode.IGNORE -> Unit
            Mode.FORWARD -> if (view.zoomEnabled && e.pointerCount == 2 && abs(distance(e) - startDistance) > slop) startPinch(e, now)
                else forward(e, (0 until e.pointerCount).toList(), TouchPhase.MOVED, now)
        }
    }

    private fun pointerUp(e: MotionEvent, now: Long) {
        when (mode) {
            Mode.PENDING_TWO -> twoFingerTapEnded(now)
            Mode.PINCH, Mode.PAN, Mode.IGNORE -> mode = Mode.IGNORE
            Mode.FORWARD -> forward(e, listOf(e.actionIndex), TouchPhase.ENDED, now)
        }
    }

    private fun up(e: MotionEvent, now: Long) {
        if (mode == Mode.FORWARD) forward(e, listOf(0), TouchPhase.ENDED, now)
        mode = Mode.FORWARD
        forwarded.clear()
        view.sequenceEnded()
    }

    private fun startPinch(e: MotionEvent, now: Long) {
        cancelForwarded(now)
        mode = Mode.PINCH
        lastDistance = distance(e)
        track(e)
    }

    private fun pinch(e: MotionEvent) {
        if (e.pointerCount < 2) return
        val d = distance(e)
        val (cx, cy) = centroid(e)
        view.mapper?.let { m ->
            val moved = view.viewport.panned(cx - lastCx, cy - lastCy, m)
            view.setViewport(moved.zoomed(if (lastDistance > 0f) d / lastDistance else 1f, cx, cy + view.panY, m))
        }
        lastDistance = d; lastCx = cx; lastCy = cy
    }

    private fun pan(e: MotionEvent) {
        val (cx, cy) = centroid(e)
        view.mapper?.let { view.setViewport(view.viewport.panned(cx - lastCx, cy - lastCy, it)) }
        lastCx = cx; lastCy = cy
    }

    /** Hai ngón vừa chạm khi đang zoom: chưa biết là chụm, cuộn hay chạm; chờ ngón dịch quá ngưỡng rồi mới quyết. */
    private fun pending(e: MotionEvent, now: Long) {
        if (e.pointerCount != 2) return
        if (abs(distance(e) - startDistance) > slop) return startPinch(e, now)
        val (cx, cy) = centroid(e)
        if (hypot(cx - lastCx, cy - lastCy) > slop) {
            mode = Mode.FORWARD
            forward(e, listOf(0, 1), TouchPhase.BEGAN, now)
        }
    }

    private fun twoFingerTapEnded(now: Long) {
        mode = Mode.IGNORE
        if (now - twoStartMs > TAP_MS) return
        if (now - lastTwoFingerTapMs <= DOUBLE_TAP_MS) { lastTwoFingerTapMs = 0L; view.resetZoom() } else lastTwoFingerTapMs = now
    }

    private fun forward(e: MotionEvent, indices: List<Int>, phase: TouchPhase, now: Long) {
        val samples = indices.mapNotNull { i -> view.sample(e.getPointerId(i), e.getX(i), e.getY(i), phase, now, forwarded) }
        if (samples.isEmpty()) return
        when (phase) { TouchPhase.BEGAN -> forwarded += samples.map { it.id }; TouchPhase.ENDED -> forwarded -= samples.map { it.id }.toSet(); else -> Unit }
        view.router?.onTouch(samples, view.displayedVideoWidthDp())
        view.afterForward()
    }

    private fun cancelForwarded(now: Long) {
        if (forwarded.isEmpty()) return
        view.router?.onTouch(forwarded.map { TouchSample(it, 0f, 0f, TouchPhase.CANCELLED, now) })
        forwarded.clear()
    }

    private fun track(e: MotionEvent) { centroid(e).let { lastCx = it.first; lastCy = it.second } }

    private fun centroid(e: MotionEvent): Pair<Float, Float> {
        var x = 0f
        var y = 0f
        for (i in 0 until e.pointerCount) { x += e.getX(i); y += e.getY(i) }
        return x / e.pointerCount to y / e.pointerCount
    }

    private fun distance(e: MotionEvent) = if (e.pointerCount < 2) 0f else hypot(e.getX(0) - e.getX(1), e.getY(0) - e.getY(1))
    private fun abs(v: Float) = if (v < 0f) -v else v

    private companion object {
        const val SLOP_DP = 14f
        const val TAP_MS = 300L
        const val DOUBLE_TAP_MS = 450L
    }
}
