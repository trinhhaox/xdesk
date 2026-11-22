package vn.xox.xdesk.app.ui

import android.provider.OpenableColumns
import android.view.SurfaceHolder
import android.view.Window
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.foundation.shape.RoundedCornerShape
import kotlin.math.roundToInt
import vn.xox.xdesk.transport.FileTransferDirection
import vn.xox.xdesk.transport.FileTransferProgress
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
import vn.xox.xdesk.app.WorkMode
import vn.xox.xdesk.app.clearViewport
import vn.xox.xdesk.app.onViewportChanged
import vn.xox.xdesk.app.switchFit
import vn.xox.xdesk.app.switchWorkMode

/**
 * Toàn màn hình (immersive): một [StreamViewport] aspect-fit trong vùng đã trừ tai thỏ, đúng vùng đã xin host qua `display.config`.
 * Khi bàn phím mở, video dịch lên (không thu nhỏ) để vùng vừa chạm nằm trên bàn phím; thanh phím phụ bám trên bàn phím theo animation IME.
 * Nút nổi vẽ SAU khung video trong cùng Box nên luôn nằm trên và nhận chạm trước, ở mọi chế độ chuột, khi zoom và cả khi bàn phím mở.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
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
            var displayName = uri.lastPathSegment?.substringAfterLast('/') ?: "file"
            var fileSize = 0L
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (nameIdx >= 0) cursor.getString(nameIdx)?.takeIf { s -> s.isNotBlank() }?.let { n -> displayName = n }
                    if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) fileSize = cursor.getLong(sizeIdx)
                }
            }
            controller.sendFileStream(displayName, fileSize) { context.contentResolver.openInputStream(uri) }
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

    if (controller.isControlMode) {
        Box(Modifier.fillMaxSize()) {
            RemoteTrackpadSheet(
                controller = controller,
                activeMode = controller.activeWorkMode,
                onSelectMode = controller::switchWorkMode,
                isFullscreen = true,
                onDismiss = controller::disconnect
            )
            Overlay(controller, waitForFrame = false)
        }
        return
    }

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
        controller.activeFileTransfer?.let { transfer ->
            FileTransferBanner(transfer, onCancel = controller::cancelFileTransfer)
        }
        val actions = floatingActions(
            controller, pointerStore, zoomed,
            onResetZoom = { viewRef?.resetZoom() },
            onSendFile = { filePickerLauncher.launch("*/*") },
        ) { showPointerSettings = true }
        val quickDock = quickDockShortcuts(
            controller,
            keyboardShown = imeBottom > 0,
            onKeyboard = { if (imeBottom > 0) viewRef?.surfaceView?.hideKeyboard() else viewRef?.surfaceView?.showKeyboard() },
        )
        val macShortcuts = macQuickShortcuts(controller, context)
        if (!controller.awaitingFrame && controller.sasPrompt == null) {
            FloatingControl(
                store = floatingStore,
                status = controller.stats,
                activeWorkMode = controller.activeWorkMode,
                onSelectWorkMode = controller::switchWorkMode,
                actions = actions,
                quickDock = quickDock,
                macShortcuts = macShortcuts,
                activeMirrorFit = controller.display.fit.takeIf { controller.streaming && controller.activeWorkMode == WorkMode.MIRROR },
                onSelectMirrorFit = controller::switchFit,
                hostDisplays = if (controller.streaming && controller.activeWorkMode == WorkMode.MIRROR) controller.hostDisplays else emptyList(),
                selectedDisplayId = controller.selectedDisplayId,
                onSelectHostDisplay = controller::selectHostDisplay,
                modifier = Modifier.padding(bottom = with(density) { obscured.toDp() }),
            )
        }
        controller.input?.takeIf { imeBottom > 0 }?.let {
            KeyBar(it, onHide = { viewRef?.surfaceView?.hideKeyboard() }, modifier = Modifier.align(Alignment.BottomCenter).imePadding())
        }
        controller.clipboardNotice?.let { notice ->
            ClipboardToast(notice, Modifier.align(Alignment.Center).padding(horizontal = 24.dp))
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
    controller: ViewerController, store: PointerSettingsStore, zoomed: Boolean,
    onResetZoom: () -> Unit, onSendFile: () -> Unit, onPointerSettings: () -> Unit,
) = buildList {
    add(
        FloatingAction(
            label = "Chuột: ${store.settings.mode.title()}",
            icon = if (store.settings.mode == PointerMode.DIRECT) XdeskIcons.HandTap else XdeskIcons.Cursor,
            description = "Đổi chế độ chuột, đang là ${store.settings.mode.title()}",
            trailingIcon = XdeskIcons.Sliders,
            trailingDescription = "Cài đặt chuột và con trỏ",
            onTrailingClick = onPointerSettings,
            onClick = store::toggleMode,
        ),
    )
    if (controller.audioAvailable) {
        add(
            FloatingAction(
                label = if (controller.audioMuted) "Âm thanh: Đã tắt" else "Âm thanh: Bật",
                icon = if (controller.audioMuted) XdeskIcons.VolumeOff else XdeskIcons.VolumeUp,
                description = if (controller.audioMuted) "Bật lại tiếng trên điện thoại" else "Tắt tiếng trên điện thoại",
                onClick = controller::toggleAudioMute,
            ),
        )
    }
    if (zoomed) add(FloatingAction("Vừa khung màn hình", XdeskIcons.FitScreen, "Thu về vừa khung màn hình", onClick = onResetZoom))
    if (controller.clipboardAvailable) {
        add(FloatingAction("Gửi clipboard sang Mac", XdeskIcons.Clipboard, "Gửi clipboard sang máy Mac", afterShortcuts = true, onClick = controller::sendClipboardToMac))
    }
    add(FloatingAction("Gửi tệp sang Mac…", XdeskIcons.FileTransfer, "Gửi tệp sang máy Mac", afterShortcuts = true, onClick = onSendFile))
    add(FloatingAction("Ngắt kết nối", XdeskIcons.Stop, isDestructive = true, onClick = controller::disconnect))
}

private fun quickDockShortcuts(
    controller: ViewerController,
    keyboardShown: Boolean,
    onKeyboard: () -> Unit,
) = listOf(
    DockShortcut(if (keyboardShown) "Ẩn phím" else "Bàn phím", XdeskIcons.Keyboard, if (keyboardShown) "Ẩn bàn phím" else "Hiện bàn phím", enabled = controller.streaming, onClick = onKeyboard),
    DockShortcut("Khoá Mac", XdeskIcons.Lock, "Khóa máy Mac") { controller.sendSystemLock() },
    DockShortcut("Chụp ảnh", XdeskIcons.Camera, "Chụp vùng màn hình Mac (⌘ ⇧ 4)") { controller.input?.tapKey(0x21, 9) },
)

private fun macQuickShortcuts(controller: ViewerController, context: android.content.Context) = listOf(
    DockShortcut("Spotlight (⌘ Space)", XdeskIcons.Search) { controller.input?.tapKey(0x2C, 8) },
    DockShortcut("Mission Control (⌃ ↑)", XdeskIcons.Layers) { controller.input?.tapKey(0x52, 2) },
    DockShortcut("Chuyển app (⌘ Tab)", XdeskIcons.AppWindow) { controller.input?.tapKey(0x2B, 8) },
    DockShortcut("Hoàn tác (⌘ Z)", XdeskIcons.Undo) { controller.input?.tapKey(0x1D, 8) },
    DockShortcut("Mở khoá Mac", XdeskIcons.Unlock) { unlockMacWithBiometrics(controller, context) },
)

private fun unlockMacWithBiometrics(controller: ViewerController, context: android.content.Context) {
    val activity = context as? FragmentActivity ?: run {
        controller.showToast("Cần xác thực vân tay / khoá màn hình để mở khoá Mac")
        return
    }
    val authenticators = BiometricManager.Authenticators.BIOMETRIC_STRONG or
        BiometricManager.Authenticators.BIOMETRIC_WEAK or
        BiometricManager.Authenticators.DEVICE_CREDENTIAL
    val status = BiometricManager.from(activity).canAuthenticate(authenticators)
    if (status != BiometricManager.BIOMETRIC_SUCCESS) {
        controller.showToast("Cần bật vân tay / khoá màn hình trên điện thoại để mở khoá Mac")
        return
    }
    val executor = ContextCompat.getMainExecutor(activity)
    val prompt = BiometricPrompt(
        activity,
        executor,
        object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                controller.sendSystemUnlock()
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                controller.showToast("Đã huỷ xác thực mở khoá Mac")
            }
        },
    )
    val info = BiometricPrompt.PromptInfo.Builder()
        .setTitle("Mở khoá máy Mac")
        .setSubtitle("Xác thực sinh trắc học hoặc mã khoá điện thoại để tiếp tục")
        .setAllowedAuthenticators(authenticators)
        .build()
    prompt.authenticate(info)
}

@Composable
private fun FileTransferBanner(transfer: FileTransferProgress, onCancel: () -> Unit) {
    val percent = (transfer.fraction * 100f).roundToInt()
    Box(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        contentAlignment = Alignment.TopCenter,
    ) {
        Row(
            Modifier.background(XdeskOverlay.bar, shape = RoundedCornerShape(12.dp))
                .padding(horizontal = 14.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    "${if (transfer.direction == FileTransferDirection.SENDING) "Đang gửi" else "Đang nhận"} ${transfer.fileName} ($percent%)",
                    color = XdeskOverlay.content,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 12.sp,
                    maxLines = 1,
                )
                LinearProgressIndicator(progress = { transfer.fraction }, modifier = Modifier.fillMaxWidth())
            }
            TextButton(onClick = onCancel) {
                Text("Huỷ", color = XdeskOverlay.content, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun ClipboardToast(text: String, modifier: Modifier = Modifier) {
    Box(
        modifier
            .background(XdeskOverlay.bar, shape = androidx.compose.foundation.shape.RoundedCornerShape(50))
            .padding(horizontal = 16.dp, vertical = 9.dp),
    ) {
        Text(
            text,
            color = XdeskOverlay.content,
            fontSize = 14.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
        )
    }
}

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
                .background(XdeskOverlay.bar, shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp))
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Column(Modifier.weight(1f)) {
                Text("Agent AI cần trợ giúp", color = XdeskOverlay.warning, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                Text(reason, color = XdeskOverlay.content, fontSize = 12.sp, maxLines = 2)
            }
            Button(
                onClick = onResolved,
                colors = ButtonDefaults.buttonColors(containerColor = XdeskOverlay.good, contentColor = XdeskOverlay.content)
            ) {
                Text("Đã xong", fontSize = 12.sp)
            }
        }
    }
}

/** Mã SAS có lớp phủ riêng; còn lại, từ lúc chạm Mac tới khung hình đầu tiên là lớp phủ "Đang kết nối" có nút Huỷ. */
@Composable
private fun Overlay(controller: ViewerController, waitForFrame: Boolean = true) {
    val prompt = controller.sasPrompt
    if (prompt != null) {
        Box(Modifier.fillMaxSize().background(XdeskOverlay.scrim), contentAlignment = Alignment.Center) { SasCodeView(prompt) }
    } else if (controller.reconnectAttempt > 0 || (if (waitForFrame) controller.awaitingFrame else controller.connecting)) {
        ConnectingOverlay(controller.progress.targetName, controller.reconnectAttempt, onCancel = controller::disconnect)
    }
}

/** Nền đen đặc để không lộ khung hình dở dang và chặn chạm (không gửi click xuống Mac khi chưa có hình); thẻ giữa giống iOS: vòng quay, tên máy, "Huỷ". */
@Composable
private fun ConnectingOverlay(name: String, reconnectAttempt: Int, onCancel: () -> Unit) {
    val message = when {
        reconnectAttempt > 0 && name.isBlank() -> "Đang kết nối lại (lần $reconnectAttempt/3)…"
        reconnectAttempt > 0 -> "Đang kết nối lại tới $name (lần $reconnectAttempt/3)…"
        name.isBlank() -> "Đang kết nối…"
        else -> "Đang kết nối tới $name…"
    }
    Box(Modifier.fillMaxSize().background(Color.Black).pointerInput(Unit) { detectTapGestures { } }, contentAlignment = Alignment.Center) {
        OverlayCard {
            CircularProgressIndicator(color = XdeskOverlay.accentLight)
            Text(
                message, color = XdeskOverlay.content, fontSize = 17.sp, fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
            )
            OutlinedButton(
                onCancel, Modifier.widthIn(min = 120.dp).heightIn(min = 48.dp), border = BorderStroke(1.dp, XdeskOverlay.outline),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = XdeskOverlay.content),
            ) { Text("Huỷ") }
        }
    }
}
