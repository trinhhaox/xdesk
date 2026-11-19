package vn.xox.xdesk.app.ui

import android.content.Context
import android.os.SystemClock
import android.text.InputType
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import vn.xox.xdesk.app.StreamInputRouter
import vn.xox.xdesk.app.input.HidKeys
import vn.xox.xdesk.app.input.TouchPhase
import vn.xox.xdesk.app.input.TouchSample

/**
 * SurfaceView (không TextureView: đường compositor ngắn nhất) nhận cảm ứng → [StreamInputRouter] và đóng vai ô gõ cho IME:
 * chữ chốt của bộ gõ Telex đi `input.text`, phím cứng/đặc biệt đi HID. Bản thân view không giữ chữ nào.
 */
class StreamSurfaceView(context: Context) : SurfaceView(context) {
    var router: StreamInputRouter? = null
    var onSurface: (SurfaceHolder?, Int, Int) -> Unit = { _, _, _ -> }
    private val tick = object : Runnable {
        override fun run() {
            router?.tick()
            postDelayed(this, TICK_MS)
        }
    }

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(h: SurfaceHolder) = onSurface(h, width, height)
            override fun surfaceChanged(h: SurfaceHolder, format: Int, w: Int, h2: Int) = onSurface(h, w, h2)
            override fun surfaceDestroyed(h: SurfaceHolder) = onSurface(null, 0, 0)
        })
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        post(tick)
    }

    override fun onDetachedFromWindow() {
        removeCallbacks(tick)
        super.onDetachedFromWindow()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val target = router ?: return false
        val phase = when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> TouchPhase.BEGAN
            MotionEvent.ACTION_MOVE -> TouchPhase.MOVED
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> TouchPhase.ENDED
            MotionEvent.ACTION_CANCEL -> TouchPhase.CANCELLED
            else -> return false
        }
        val now = SystemClock.uptimeMillis()
        val indices = when (phase) {
            TouchPhase.MOVED, TouchPhase.CANCELLED -> (0 until event.pointerCount).toList()
            else -> listOf(event.actionIndex)
        }
        target.onTouch(indices.map { sample(event, it, phase, now) })
        return true
    }

    private fun sample(e: MotionEvent, index: Int, phase: TouchPhase, now: Long) = TouchSample(
        e.getPointerId(index), (e.getX(index) / width).coerceIn(0f, 1f), (e.getY(index) / height).coerceIn(0f, 1f), phase, now,
    )

    fun showKeyboard() {
        requestFocus()
        (context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).showSoftInput(this, 0)
    }

    fun hideKeyboard() {
        (context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(windowToken, 0)
    }

    override fun onCheckIsTextEditor() = true

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        outAttrs.inputType = InputType.TYPE_CLASS_TEXT
        outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI or EditorInfo.IME_FLAG_NO_FULLSCREEN or EditorInfo.IME_ACTION_NONE
        return RemoteInputConnection(this)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean = forwardKey(keyCode, event) || super.onKeyDown(keyCode, event)

    private fun forwardKey(keyCode: Int, event: KeyEvent): Boolean {
        val usage = HidKeys.fromAndroid(keyCode) ?: return false
        router?.tapKey(usage, HidKeys.modifiers(event.metaState))
        return router != null
    }

    private inner class RemoteInputConnection(view: android.view.View) : BaseInputConnection(view, false) {
        override fun commitText(text: CharSequence, newCursorPosition: Int): Boolean { router?.commitText(text.toString()); return true }
        override fun setComposingText(text: CharSequence, newCursorPosition: Int): Boolean { router?.setComposing(text.toString()); return true }
        override fun finishComposingText(): Boolean { router?.finishComposing(); return true }
        override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean { router?.deleteBefore(beforeLength); return true }

        override fun sendKeyEvent(event: KeyEvent): Boolean {
            if (event.action != KeyEvent.ACTION_DOWN) return true
            return forwardKey(event.keyCode, event)
        }
    }

    private companion object { const val TICK_MS = 50L }
}
