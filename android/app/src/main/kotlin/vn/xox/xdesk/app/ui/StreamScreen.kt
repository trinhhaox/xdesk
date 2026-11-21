package vn.xox.xdesk.app.ui

import android.view.SurfaceHolder
import android.view.Window
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import vn.xox.xdesk.app.ui.theme.XdeskOverlay
import vn.xox.xdesk.app.awaitingFrame
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ButtonDefaults
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.BorderStroke
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
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import kotlinx.coroutines.delay
import vn.xox.xdesk.app.FloatingControlStore
import vn.xox.xdesk.app.PointerSettingsStore
import vn.xox.xdesk.app.input.PointerMode
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.clearViewport
import vn.xox.xdesk.app.onViewportChanged
import vn.xox.xdesk.app.switchFit
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
    val context = LocalContext.current
    val filePickerLauncher = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        uri?.let {
            val name = uri.lastPathSegment?.substringAfterLast('/') ?: "file"
            val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            if (bytes != null) controller.sendFile(name, bytes)
        }
    }
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
        controller.agentHelp?.takeIf { controller.streaming }?.let { help ->
            AgentHelpBanner(help.reason, onResolved = { controller.resolveAgentHelp(help.id) })
        }
        val actions = floatingActions(controller, pointerStore, zoomed, keyboardShown = imeBottom > 0, onKeyboard = { if (imeBottom > 0) viewRef?.surfaceView?.hideKeyboard() else viewRef?.surfaceView?.showKeyboard() }, onResetZoom = { viewRef?.resetZoom() }, onSendFile = { filePickerLauncher.launch("*/*") }) { showPointerSettings = true }
        val shortcuts = dockShortcuts(controller)
        if (!controller.awaitingFrame && controller.sasPrompt == null) FloatingControl(floatingStore, controller.stats, actions, shortcuts, Modifier.padding(bottom = with(density) { obscured.toDp() }))
        controller.input?.takeIf { imeBottom > 0 }?.let {
            KeyBar(it, onHide = { viewRef?.surfaceView?.hideKeyboard() }, modifier = Modifier.align(Alignment.BottomCenter).imePadding())
        }
    }
    if (showPointerSettings) {
        AlertDialog(
            onDismissRequest = { showPointerSettings = false },
            title = { Text("Chuột và con trỏ") }, text = { PointerSettingsGroups(pointerStore, Modifier.verticalScroll(rememberScrollState())) },
            confirmButton = { TextButton(onClick = { showPointerSettings = false }) { Text("Xong") } },
        )
    }
}

private fun floatingActions(
    controller: ViewerController, store: PointerSettingsStore, zoomed: Boolean, keyboardShown: Boolean,
    onKeyboard: () -> Unit, onResetZoom: () -> Unit, onSendFile: () -> Unit, onPointerSettings: () -> Unit,
) = buildList {
    add(FloatingAction("Ngắt kết nối", XdeskIcons.Stop, onClick = controller::disconnect))
    add(FloatingAction(if (keyboardShown) "Ẩn bàn phím" else "Bàn phím", XdeskIcons.Keyboard, onClick = onKeyboard))
    add(FloatingAction("Chuột: ${store.settings.mode.title()}", if (store.settings.mode == PointerMode.DIRECT) XdeskIcons.HandTap else XdeskIcons.Cursor, "Đổi chế độ chuột, đang là ${store.settings.mode.title()}", onClick = store::toggleMode))
    add(FloatingAction("Cài đặt chuột", XdeskIcons.Sliders, "Cài đặt chuột và con trỏ", onClick = onPointerSettings))
    if (zoomed) add(FloatingAction("Vừa khung màn hình", XdeskIcons.FitScreen, "Thu về vừa khung màn hình", onClick = onResetZoom))
    controller.nextFit()?.let { next -> add(FloatingAction("Kiểu: ${controller.display.fit.title()}", XdeskIcons.Laptop, "Đổi kiểu Bản sao sang ${next.title()}, kết nối lại") { controller.switchFit(next) }) }
    add(FloatingAction("Chụp màn hình Mac", XdeskIcons.Camera, "Chụp vùng màn hình (⌘ ⇧ 4)") { controller.input?.tapKey(0x21, 9) })
    add(FloatingAction("Gửi tệp sang Mac", XdeskIcons.FileTransfer, "Gửi tệp sang máy Mac", onClick = onSendFile))
}

private fun dockShortcuts(controller: ViewerController) = listOf(
    DockShortcut("Spotlight", XdeskIcons.Search, "Tìm kiếm Spotlight (⌘ Space)") {
        controller.input?.tapKey(0x2C, 8)
    },
    DockShortcut("Mission Control", XdeskIcons.Layers, "Mission Control (⌃ ↑)") {
        controller.input?.tapKey(0x52, 2)
    },
    DockShortcut("App Switcher", XdeskIcons.AppWindow, "Chuyển ứng dụng (⌘ Tab)") {
        controller.input?.tapKey(0x2B, 8)
    },
    DockShortcut("Undo", XdeskIcons.Undo, "Hoàn tác (⌘ Z)") {
        controller.input?.tapKey(0x1D, 8)
    },
    DockShortcut("Lock", XdeskIcons.Lock, "Khóa máy Mac") {
        controller.sendSystemLock()
    },
    DockShortcut("Unlock", XdeskIcons.Unlock, "Mở khóa/đánh thức Mac") {
        controller.sendSystemUnlock()
    },
)

@Composable
private fun AgentHelpBanner(reason: String, onResolved: () -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        contentAlignment = Alignment.TopCenter
    ) {
        Row(
            Modifier
                .background(Color(0xFF1E1E1E), shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp))
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Column(Modifier.weight(1f)) {
                Text("Agent AI cần trợ giúp", color = Color(0xFFFFB74D), fontWeight = FontWeight.Bold, fontSize = 13.sp)
                Text(reason, color = Color.White, fontSize = 12.sp, maxLines = 2)
            }
            Button(
                onClick = onResolved,
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2E7D32), contentColor = Color.White)
            ) {
                Text("Đã xong", fontSize = 12.sp)
            }
        }
    }
}

/** Mã SAS có lớp phủ riêng; còn lại, từ lúc chạm Mac tới khung hình đầu tiên là lớp phủ "Đang kết nối" có nút Huỷ. */
@Composable
private fun Overlay(controller: ViewerController) {
    val prompt = controller.sasPrompt
    if (prompt != null) {
        Box(Modifier.fillMaxSize().background(XdeskOverlay.scrim), contentAlignment = Alignment.Center) { SasCodeView(prompt) }
    } else if (controller.awaitingFrame) {
        ConnectingOverlay(controller.progress.targetName, onCancel = controller::disconnect)
    }
}

/** Nền đen đặc để không lộ khung hình dở dang và chặn chạm (không gửi click xuống Mac khi chưa có hình); thẻ giữa giống iOS: vòng quay, tên máy, "Huỷ". */
@Composable
private fun ConnectingOverlay(name: String, onCancel: () -> Unit) {
    Box(Modifier.fillMaxSize().background(Color.Black).pointerInput(Unit) { detectTapGestures { } }, contentAlignment = Alignment.Center) {
        OverlayCard {
            CircularProgressIndicator(color = XdeskOverlay.accentLight)
            Text(
                if (name.isBlank()) "Đang kết nối…" else "Đang kết nối tới $name…", color = XdeskOverlay.content, fontSize = 17.sp, fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
            )
            OutlinedButton(
                onCancel, Modifier.widthIn(min = 120.dp).heightIn(min = 48.dp), border = BorderStroke(1.dp, XdeskOverlay.outline),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = XdeskOverlay.content),
            ) { Text("Huỷ") }
        }
    }
}
