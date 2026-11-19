package vn.xox.xdesk.app.ui

import android.view.SurfaceHolder
import android.view.Window
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import kotlinx.coroutines.delay
import vn.xox.xdesk.app.ViewerController

/** Toàn màn hình (immersive) trên một SurfaceView; xoay máy được Activity giữ nguyên (configChanges) và controller mở lại phiên với kích thước mới. */
@Composable
fun StreamScreen(controller: ViewerController, window: Window) {
    var showBars by remember { mutableStateOf(true) }
    var showKeys by remember { mutableStateOf(false) }
    var viewRef by remember { mutableStateOf<StreamSurfaceView?>(null) }

    DisposableEffect(Unit) {
        val insets = WindowCompat.getInsetsController(window, window.decorView)
        insets.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        insets.hide(WindowInsetsCompat.Type.systemBars())
        onDispose { insets.show(WindowInsetsCompat.Type.systemBars()) }
    }
    LaunchedEffect(controller.streaming) {
        while (controller.streaming) { controller.refreshStats(); delay(1000) }
    }
    LaunchedEffect(showBars) { if (showBars) { delay(4000); showBars = false } }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(modifier = Modifier.fillMaxSize(), factory = { ctx ->
            StreamSurfaceView(ctx).also { view ->
                view.router = controller.input
                view.onSurface = { holder: SurfaceHolder?, w, h -> surfaceChanged(controller, holder, w, h) }
                viewRef = view
            }
        }, update = { it.router = controller.input })

        Overlay(controller)
        controller.agentApproval?.takeIf { controller.streaming }?.let { AgentApprovalDialog(it, controller::answerAgentApproval) }
        if (showBars || !controller.streaming) {
            TopBar(controller, onKeyboard = { viewRef?.showKeyboard() }, onKeys = { showKeys = !showKeys }, modifier = Modifier.align(Alignment.TopCenter))
        } else {
            TextButton(onClick = { showBars = true }, modifier = Modifier.align(Alignment.TopEnd)) { Text("⋯") }
        }
        controller.input?.let { if (showKeys) KeyBar(it, Modifier.align(Alignment.BottomCenter).fillMaxWidth()) }
    }
}

private fun surfaceChanged(controller: ViewerController, holder: SurfaceHolder?, w: Int, h: Int) {
    if (holder == null) controller.detachSurface() else {
        controller.attachSurface(holder.surface)
        controller.onSurfaceResized(w, h)
    }
}

@Composable
private fun TopBar(controller: ViewerController, onKeyboard: () -> Unit, onKeys: () -> Unit, modifier: Modifier) {
    Row(modifier.fillMaxWidth().background(Color(0x99000000)).padding(8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(controller.stats, color = Color.White, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
        TextButton(onClick = onKeyboard) { Text("Bàn phím") }
        TextButton(onClick = onKeys) { Text("Phím") }
        Button(onClick = controller::disconnect) { Text("Ngắt") }
    }
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
