package vn.xox.xdesk.app.ui

import android.view.SurfaceHolder
import android.view.Window
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import kotlinx.coroutines.delay
import vn.xox.xdesk.app.FloatingControlStore
import vn.xox.xdesk.app.PointerSettingsStore
import vn.xox.xdesk.app.StreamInputRouter
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.input.VideoPan

private const val CURSOR_VISIBLE_MS = 1500L

/**
 * Toàn màn hình (immersive) trên một SurfaceView; xoay máy được Activity giữ nguyên (configChanges) và controller mở lại phiên với kích thước mới.
 * Khi bàn phím mở, video dịch lên (không thu nhỏ) để vùng vừa chạm nằm trên bàn phím; thanh phím phụ bám trên bàn phím theo animation IME.
 */
@Composable
fun StreamScreen(controller: ViewerController, window: Window) {
    val pointerStore = remember { PointerSettingsStore(window.context) }
    val floatingStore = remember { FloatingControlStore(window.context) }
    var showPointerSettings by remember { mutableStateOf(false) }
    var viewRef by remember { mutableStateOf<StreamSurfaceView?>(null) }
    var viewHeight by remember { mutableIntStateOf(0) }
    val density = LocalDensity.current
    val imeBottom = WindowInsets.ime.getBottom(density)
    val keyBarPx = with(density) { KeyBarHeight.toPx() }
    val obscured = if (imeBottom > 0) imeBottom + keyBarPx else 0f
    val focus = controller.input?.focusY
    val targetPan = if (focus == null || viewHeight == 0) 0f else VideoPan.offset(focus * viewHeight, viewHeight.toFloat(), obscured, viewHeight.toFloat())
    val pan by animateFloatAsState(targetPan, tween(120), label = "keyboard-pan")

    SideEffect {
        controller.input?.applySettings(pointerStore.settings)
        viewRef?.translationY = -pan
    }
    DisposableEffect(Unit) {
        val insets = WindowCompat.getInsetsController(window, window.decorView)
        insets.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        insets.hide(WindowInsetsCompat.Type.systemBars())
        onDispose { insets.show(WindowInsetsCompat.Type.systemBars()) }
    }
    LaunchedEffect(controller.streaming) {
        while (controller.streaming) { controller.refreshStats(); delay(1000) }
    }

    Box(Modifier.fillMaxSize().background(Color.Black).onSizeChanged { viewHeight = it.height }) {
        AndroidView(modifier = Modifier.fillMaxSize(), factory = { ctx ->
            StreamSurfaceView(ctx).also { view ->
                view.router = controller.input
                view.onSurface = { holder: SurfaceHolder?, w, h -> surfaceChanged(controller, holder, w, h) }
                viewRef = view
            }
        }, update = { it.router = controller.input })

        CursorOverlay(controller.input) { pan }
        Overlay(controller)
        controller.agentApproval?.takeIf { controller.streaming }?.let { AgentApprovalDialog(it, controller::answerAgentApproval) }
        if (imeBottom == 0) FloatingControl(floatingStore, controller.stats, floatingActions(controller, pointerStore, onKeyboard = { viewRef?.showKeyboard() }) { showPointerSettings = true })
        controller.input?.takeIf { imeBottom > 0 }?.let {
            KeyBar(it, onHide = { viewRef?.hideKeyboard() }, modifier = Modifier.align(Alignment.BottomCenter).imePadding())
        }
    }
    if (showPointerSettings) {
        AlertDialog(
            onDismissRequest = { showPointerSettings = false },
            text = { PointerSettingsCard(pointerStore) },
            confirmButton = { TextButton(onClick = { showPointerSettings = false }) { Text("Xong") } },
        )
    }
}

private fun surfaceChanged(controller: ViewerController, holder: SurfaceHolder?, w: Int, h: Int) {
    if (holder == null) controller.detachSurface() else {
        controller.attachSurface(holder.surface)
        controller.onSurfaceResized(w, h)
    }
}

/** Con trỏ cục bộ của chế độ trackpad: hiện khi đang trượt và 1,5 s sau đó; vẽ ngay không chờ video có con trỏ Mac. */
@Composable
private fun CursorOverlay(router: StreamInputRouter?, pan: () -> Float) {
    val cursor = router?.cursor ?: return
    var visible by remember { mutableStateOf(false) }
    LaunchedEffect(router.cursorStamp) { visible = true; delay(CURSOR_VISIBLE_MS); visible = false }
    if (!visible) return
    Canvas(Modifier.fillMaxSize().graphicsLayer { translationY = -pan() }) {
        val tip = Offset(cursor.first * size.width, cursor.second * size.height)
        val unit = density
        val arrow = Path().apply {
            moveTo(tip.x, tip.y)
            lineTo(tip.x, tip.y + 17 * unit)
            lineTo(tip.x + 4.2f * unit, tip.y + 13.2f * unit)
            lineTo(tip.x + 7 * unit, tip.y + 19.5f * unit)
            lineTo(tip.x + 9.8f * unit, tip.y + 18.3f * unit)
            lineTo(tip.x + 7 * unit, tip.y + 12.2f * unit)
            lineTo(tip.x + 12 * unit, tip.y + 12.2f * unit)
            close()
        }
        drawPath(arrow, Color.White)
        drawPath(arrow, Color.Black, style = Stroke(1.2f * unit))
    }
}

private fun floatingActions(controller: ViewerController, store: PointerSettingsStore, onKeyboard: () -> Unit, onPointerSettings: () -> Unit) = listOf(
    FloatingAction("Ngắt kết nối", onClick = controller::disconnect),
    FloatingAction("Bàn phím", onClick = onKeyboard),
    FloatingAction("Chuột: ${store.settings.mode.title()}", "Đổi chế độ chuột, đang là ${store.settings.mode.title()}", onClick = store::toggleMode),
    FloatingAction("Cài đặt chuột", "Cài đặt chuột và con trỏ", onClick = onPointerSettings),
)

@Composable
private fun Overlay(controller: ViewerController) {
    val code = controller.sasCode
    if (code != null) {
        Column(Modifier.fillMaxSize().background(Color(0xE6000000)), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            SasCodeView(code)
        }
    } else if (controller.connecting) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator()
            Text("Đang kết nối…", color = Color.White, modifier = Modifier.padding(top = 12.dp))
        }
    }
}
