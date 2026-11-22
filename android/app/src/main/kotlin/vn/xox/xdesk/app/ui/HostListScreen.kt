package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import vn.xox.xdesk.app.Screen
import vn.xox.xdesk.app.TailscaleState
import vn.xox.xdesk.app.TailscaleSupport
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.WorkMode
import vn.xox.xdesk.app.connectManual
import vn.xox.xdesk.app.connectPaired
import vn.xox.xdesk.app.directory
import vn.xox.xdesk.app.discovery.HostBadge
import vn.xox.xdesk.app.discovery.PairedEntry
import vn.xox.xdesk.app.forgetHost
import vn.xox.xdesk.app.normalizeManualAddress
import vn.xox.xdesk.app.openPairing
import vn.xox.xdesk.app.prepareForConnect
import vn.xox.xdesk.app.retry
import vn.xox.xdesk.app.ui.theme.XdeskCard
import vn.xox.xdesk.app.ui.theme.extras
import vn.xox.xdesk.transport.KnownHost
import vn.xox.xdesk.transport.ViewerTarget

private data class PendingTailscaleConnection(
    val address: String,
    val state: TailscaleState,
    val onProceed: () -> Unit,
)

/**
 * Màn chính: thanh công cụ Tìm lại / + / Cài đặt, cảnh báo Tailscale nếu kết nối qua tailnet mà Tailscale chưa bật/chưa cài,
 * "Máy Mac của bạn", "Máy Mac khác trên mạng" và "Thêm & kết nối khác".
 */
@Composable
fun HostListScreen(controller: ViewerController, onRefresh: () -> Unit) {
    val context = LocalContext.current
    @Suppress("DEPRECATION")
    val lifecycleOwner = LocalLifecycleOwner.current
    var manual by remember { mutableStateOf("") }
    var forgetting by remember { mutableStateOf<KnownHost?>(null) }
    var tailscaleState by remember { mutableStateOf(TailscaleSupport.detect(context)) }
    var pendingTailscale by remember { mutableStateOf<PendingTailscaleConnection?>(null) }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                tailscaleState = TailscaleSupport.detect(context)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val trust = controller.trust
    val directory = controller.directory
    val hasPaired = directory.paired.isNotEmpty()
    val pairedNeedsTailscale = directory.paired.any { entry ->
        entry.discovered == null && entry.known.lastAddress?.let(TailscaleSupport::isTailscaleHost) == true
    }
    val manualNeedsTailscale = TailscaleSupport.isTailscaleHost(normalizeManualAddress(manual))

    fun connectPairedWithMode(entry: PairedEntry, overrideMode: WorkMode? = null) {
        val proceed = {
            controller.prepareForConnect(overrideMode)
            controller.connectPaired(entry)
        }
        val tailAddr = if (entry.discovered == null) entry.known.lastAddress?.takeIf(TailscaleSupport::isTailscaleHost) else null
        if (tailAddr != null) {
            val state = TailscaleSupport.detect(context)
            tailscaleState = state
            if (state != TailscaleState.ACTIVE) {
                pendingTailscale = PendingTailscaleConnection(tailAddr, state, proceed)
                return
            }
        }
        proceed()
    }

    fun connectManualWithCheck(raw: String) {
        val normalized = normalizeManualAddress(raw)
        val proceed = {
            controller.prepareForConnect()
            controller.connectManual(raw)
        }
        if (TailscaleSupport.isTailscaleHost(normalized)) {
            val state = TailscaleSupport.detect(context)
            tailscaleState = state
            if (state != TailscaleState.ACTIVE) {
                pendingTailscale = PendingTailscaleConnection(normalized, state, proceed)
                return
            }
        }
        proceed()
    }

    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = XdeskDims.gutter, end = XdeskDims.gutter, top = 8.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(XdeskDims.sectionGap),
    ) {
        item {
            HomeToolbar(
                onRefresh = {
                    tailscaleState = TailscaleSupport.detect(context)
                    onRefresh()
                },
                onSettings = { controller.screen = Screen.SECURITY },
                onAdd = if (hasPaired) { { controller.openPairing(null) } } else null,
            )
            Text("Xdesk", Modifier.padding(start = 4.dp, top = 8.dp), fontSize = 34.sp, fontWeight = FontWeight.Bold, lineHeight = 41.sp)
        }
        controller.identityError?.let { item { Text("$it. Vào Cài đặt để đặt lại danh tính.", color = MaterialTheme.colorScheme.error) } }
        controller.failure?.let { failure ->
            item {
                ConnectionErrorCard(
                    failure,
                    canRepair = controller.pairTarget != null,
                    onRetry = {
                        controller.prepareForConnect()
                        controller.retry()
                    },
                    onRepair = { controller.openPairing(controller.pairTarget) },
                    onDismiss = { controller.failure = null },
                )
            }
        }
        if (tailscaleState != TailscaleState.ACTIVE && (pairedNeedsTailscale || manualNeedsTailscale)) {
            item {
                TailscaleBanner(
                    state = tailscaleState,
                    onAction = {
                        if (tailscaleState == TailscaleState.INSTALLED_INACTIVE) {
                            TailscaleSupport.openApp(context)
                        } else {
                            TailscaleSupport.openInstall(context)
                        }
                    },
                )
            }
        }
        if (!hasPaired) {
            item { EmptyPairingState { controller.openPairing(null) } }
        } else {
            item {
                val defaultIsControl = controller.display.defaultWorkMode.isControlMode
                Group("Máy Mac của bạn") {
                    directory.paired.forEachIndexed { index, entry ->
                        if (index > 0) GroupDivider(XdeskDims.rowPad + XdeskDims.iconBox + XdeskDims.iconGap)
                        PairedHostRow(
                            entry = entry,
                            secondaryIsVideo = defaultIsControl,
                            onConnect = { connectPairedWithMode(entry, null) },
                            onSecondaryAction = {
                                connectPairedWithMode(entry, if (defaultIsControl) WorkMode.MIRROR else WorkMode.TRACKPAD)
                            },
                            onForget = { forgetting = entry.known },
                        )
                    }
                }
            }
        }
        if (directory.others.isNotEmpty()) {
            item {
                Group("Máy Mac khác trên mạng") {
                    directory.others.forEachIndexed { index, host ->
                        if (index > 0) GroupDivider(XdeskDims.rowPad + XdeskDims.iconBox + XdeskDims.iconGap)
                        val badge = trust?.let { HostBadge.of(host, it) } ?: HostBadge.UNPAIRED
                        OtherHostRow(host.name, "${host.host}:${host.port}", badge) { controller.openPairing(host.toTarget()) }
                    }
                }
            }
        }
        item {
            OtherConnectionsGroup(
                address = manual,
                onAddressChange = { manual = it },
                onConnect = ::connectManualWithCheck,
                canPair = ViewerTarget.parse(normalizeManualAddress(manual)) != null,
                onPair = { controller.openPairing(ViewerTarget.parse(normalizeManualAddress(manual))) },
                tailscaleState = tailscaleState,
                onTailscaleAction = { TailscaleSupport.openOrInstall(context, tailscaleState) },
                onScanQr = if (hasPaired) { { controller.openPairing(null) } } else null,
            )
        }
    }

    forgetting?.let { host ->
        ForgetHostDialog(host, { controller.forgetHost(host.id); forgetting = null }) { forgetting = null }
    }

    pendingTailscale?.let { pending ->
        val installed = pending.state == TailscaleState.INSTALLED_INACTIVE
        AlertDialog(
            onDismissRequest = { pendingTailscale = null },
            title = { Text(if (installed) "Tailscale đang tắt" else "Chưa cài đặt Tailscale") },
            text = {
                Text(
                    if (installed) "Kết nối tới ${pending.address} cần bật Tailscale trên điện thoại trước."
                    else "Địa chỉ ${pending.address} là địa chỉ Tailscale. Cài đặt và bật Tailscale để kết nối từ xa."
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        pendingTailscale = null
                        if (installed) TailscaleSupport.openApp(context) else TailscaleSupport.openInstall(context)
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.extras.primaryFill, contentColor = Color.White),
                ) {
                    Text(if (installed) "Mở Tailscale" else "Cài đặt Tailscale")
                }
            },
            dismissButton = {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    TextButton(onClick = { pendingTailscale = null }) { Text("Đóng") }
                    TextButton(onClick = {
                        val action = pending.onProceed
                        pendingTailscale = null
                        action()
                    }) { Text("Vẫn thử kết nối") }
                }
            },
        )
    }
}

@Composable
private fun TailscaleBanner(state: TailscaleState, onAction: () -> Unit) {
    val installed = state == TailscaleState.INSTALLED_INACTIVE
    XdeskCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(horizontal = XdeskDims.rowPad, vertical = 14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                Icon(XdeskIcons.Tailscale, contentDescription = null, Modifier.padding(top = 2.dp).size(24.dp), tint = MaterialTheme.extras.warning)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        if (installed) "Tailscale đang tắt" else "Chưa cài đặt Tailscale",
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        if (installed) "Bật Tailscale để kết nối từ xa tới máy Mac qua mạng Tailscale."
                        else "Cài ứng dụng Tailscale để kết nối máy Mac từ xa ngoài mạng Wi-Fi.",
                        fontSize = 14.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Button(
                onClick = onAction,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.extras.primaryFill, contentColor = Color.White),
            ) {
                Text(if (installed) "Mở Tailscale" else "Cài đặt Tailscale", fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}
