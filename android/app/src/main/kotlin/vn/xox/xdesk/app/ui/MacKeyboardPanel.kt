package vn.xox.xdesk.app.ui

import android.os.SystemClock
import android.view.HapticFeedbackConstants
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import kotlinx.coroutines.delay
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.input.KeyboardGeometry
import vn.xox.xdesk.app.input.KeyboardGeometryCalculator
import vn.xox.xdesk.app.input.MacKey
import vn.xox.xdesk.app.input.MacKeyLayout
import vn.xox.xdesk.app.input.MacKeyboardEngine
import vn.xox.xdesk.wire.InputEvent

private const val REPEAT_POLL_MS = 20L

/**
 * Bàn phím Mac ANSI đầy đủ gửi phím vật lý (HID key down/up) để bộ gõ của chính Mac (vd. Telex) tạo chữ.
 * Tự nhả mọi phím khi rời chế độ, ra nền hoặc ngắt kết nối.
 */
@Composable
internal fun MacKeyboardPanel(controller: ViewerController, landscape: Boolean, modifier: Modifier = Modifier) {
    val engine = remember(controller.macCapsLock) { MacKeyboardEngine(controller.macCapsLock) }
    var snapshot by remember { mutableStateOf(engine.snapshot()) }
    val view = LocalView.current
    val currentController by rememberUpdatedState(controller)

    fun dispatch(events: List<InputEvent>) {
        if (events.isNotEmpty()) currentController.sendInput(events)
        snapshot = engine.snapshot()
    }

    var fnActive by remember { mutableStateOf(false) }
    val orientation = LocalConfiguration.current.orientation
    // Xoay màn hình: nhả hết phím và bỏ fn trước khi dựng lại bố cục (không kẹt phím).
    LaunchedEffect(orientation) {
        dispatch(engine.releaseAll())
        fnActive = false
    }

    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_PAUSE) dispatch(engine.releaseAll()) }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            dispatch(engine.releaseAll())
        }
    }
    LaunchedEffect(controller.streaming) {
        if (!controller.streaming) dispatch(engine.releaseAll())
    }
    LaunchedEffect(engine) {
        while (true) {
            delay(REPEAT_POLL_MS)
            val repeats = engine.tick(SystemClock.uptimeMillis())
            if (repeats.isNotEmpty()) currentController.sendInput(repeats)
        }
    }

    fun press(key: MacKey, geometry: KeyboardGeometry) {
        view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
        val now = SystemClock.uptimeMillis()
        when {
            key.kind == MacKey.Kind.FN -> fnActive = !fnActive
            MacKeyLayout.isModifier(key.usage) -> dispatch(engine.modifierDown(key.usage, now))
            else -> {
                dispatch(engine.keyDown(key.usage, now))
                if (geometry.fnLayer) fnActive = false
            }
        }
    }

    fun release(key: MacKey) {
        when {
            key.kind == MacKey.Kind.FN -> Unit
            MacKeyLayout.isModifier(key.usage) -> dispatch(engine.modifierUp(key.usage, SystemClock.uptimeMillis()))
            else -> dispatch(engine.keyUp(key.usage))
        }
    }

    BoxWithConstraints(modifier.padding(horizontal = 2.dp)) {
        val geometry = remember(maxWidth, maxHeight, landscape, fnActive) {
            KeyboardGeometryCalculator.compute(maxWidth.value, maxHeight.value, landscape, fnActive)
        }
        // key(orientation): ngón đang giữ phím bị huỷ khi đổi hướng, kèm releaseAll ở trên.
        key(orientation) {
            Box(Modifier.fillMaxSize()) {
                geometry.rects.forEachIndexed { index, rect ->
                    key(index, rect.key.usage, rect.key.label) {
                        MacKeyCap(rect, snapshot, fnActive, onDown = { press(rect.key, geometry) }, onUp = { release(rect.key) })
                    }
                }
            }
        }
    }
}
