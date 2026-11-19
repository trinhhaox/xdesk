package vn.xox.xdesk.app.ui

import android.view.SurfaceHolder
import android.view.Window
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
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
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.nextFit

/**
 * Toàn màn hình (immersive): một [StreamViewport] aspect-fit trong vùng đã trừ tai thỏ, đúng vùng đã xin host qua `display.config`.
 * Khi bàn phím mở, video dịch lên (không thu nhỏ) để vùng vừa chạm nằm trên bàn phím; thanh phím phụ bám trên bàn phím theo animation IME.
 * Nút nổi vẽ SAU khung video trong cùng Box nên luôn nằm trên và nhận chạm trước, ở mọi chế độ chuột, khi zoom và cả khi bàn phím mở.
 */
@Composable
fun StreamScreen(controller: ViewerController, window: Window) {
    val pointerStore = remember { PointerSettingsStore(window.context) }
    val floatingStore = remember { FloatingControlStore(window.context) }
    var showPointerSettings by remember { mutableStateOf(false) }
    var viewRef by remember { mutableStateOf<StreamViewport?>(null) }
    var zoomed by remember { mutableStateOf(false) }
    val density = LocalDensity.current
    val imeBottom = WindowInsets.ime.getBottom(density)
    val obscured = if (imeBottom > 0) imeBottom + with(density) { KeyBarHeight.toPx() } else 0f
    controller.input?.focusY // đọc để tính lại độ dịch khi vùng thao tác đổi
    val pan by animateFloatAsState(viewRef?.keyboardPan(obscured) ?: 0f, tween(120), label = "keyboard-pan")

    DisposableEffect(Unit) {
        val insets = WindowCompat.getInsetsController(window, window.decorView)
        insets.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        insets.hide(WindowInsetsCompat.Type.systemBars())
        onDispose { insets.show(WindowInsetsCompat.Type.systemBars()); controller.clearViewport() }
    }
    LaunchedEffect(controller.streaming) {
        while (controller.streaming) { controller.refreshStats(); delay(1000) }
    }
    LaunchedEffect(controller.input) { viewRef?.resetZoom() }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(modifier = Modifier.fillMaxSize(), factory = { ctx ->
            StreamViewport(ctx).also { view ->
                view.surfaceView.onSurface = { holder: SurfaceHolder?, _, _ -> if (holder == null) controller.detachSurface() else controller.attachSurface(holder.surface) }
                view.onViewportChanged = { zoomed = it }
                view.onSizeChanged = controller::onViewportChanged
                viewRef = view
            }
        }, update = {
            it.router = controller.input
            it.videoSize = controller.videoSize
            it.zoomEnabled = controller.isNativeMirror
            it.panY = pan
            controller.input?.applySettings(pointerStore.settings)
        })

        Overlay(controller)
        controller.agentApproval?.takeIf { controller.streaming }?.let { AgentApprovalDialog(it, controller::answerAgentApproval) }
        val actions = floatingActions(controller, pointerStore, zoomed, onKeyboard = { viewRef?.surfaceView?.showKeyboard() }, onResetZoom = { viewRef?.resetZoom() }) { showPointerSettings = true }
        FloatingControl(floatingStore, controller.stats, actions, Modifier.padding(bottom = with(density) { obscured.toDp() }))
        controller.input?.takeIf { imeBottom > 0 }?.let {
            KeyBar(it, onHide = { viewRef?.surfaceView?.hideKeyboard() }, modifier = Modifier.align(Alignment.BottomCenter).imePadding())
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

private fun floatingActions(
    controller: ViewerController, store: PointerSettingsStore, zoomed: Boolean, onKeyboard: () -> Unit, onResetZoom: () -> Unit, onPointerSettings: () -> Unit,
) = buildList {
    add(FloatingAction("Ngắt kết nối", onClick = controller::disconnect))
    add(FloatingAction("Bàn phím", onClick = onKeyboard))
    add(FloatingAction("Chuột: ${store.settings.mode.title()}", "Đổi chế độ chuột, đang là ${store.settings.mode.title()}", onClick = store::toggleMode))
    add(FloatingAction("Cài đặt chuột", "Cài đặt chuột và con trỏ", onClick = onPointerSettings))
    if (zoomed) add(FloatingAction("Vừa khung", "Thu về vừa khung màn hình", onClick = onResetZoom))
    controller.nextFit()?.let { next -> add(FloatingAction("Kiểu: ${controller.display.fit.title()}", "Đổi kiểu Bản sao sang ${next.title()}, kết nối lại") { controller.switchFit(next) }) }
}

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
