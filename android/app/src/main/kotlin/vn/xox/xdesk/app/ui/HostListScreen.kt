package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.PointerSettingsStore
import vn.xox.xdesk.app.Screen
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.connectManual
import vn.xox.xdesk.app.connectPaired
import vn.xox.xdesk.app.directory
import vn.xox.xdesk.app.discovery.HostBadge
import vn.xox.xdesk.app.forgetHost
import vn.xox.xdesk.app.openPairing
import vn.xox.xdesk.app.retry
import vn.xox.xdesk.transport.KnownHost
import vn.xox.xdesk.transport.ViewerTarget

/**
 * Màn chính dựng lại theo iOS: tiêu đề lớn "Xdesk" với viên thuốc Tìm lại + Cài đặt, nút quét QR, "Máy Mac của bạn" (kể cả khi NSD không thấy),
 * "Máy Mac khác trên mạng", dòng tóm tắt Cài đặt và "Cách kết nối khác".
 */
@Composable
fun HostListScreen(controller: ViewerController, onRefresh: () -> Unit) {
    var manual by remember { mutableStateOf("") }
    var forgetting by remember { mutableStateOf<KnownHost?>(null) }
    val pointerStore = LocalContext.current.let { context -> remember { PointerSettingsStore(context) } }
    val trust = controller.trust
    val directory = controller.directory
    LazyColumn(
        Modifier.fillMaxSize(), contentPadding = PaddingValues(start = XdeskDims.gutter, end = XdeskDims.gutter, top = 8.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(XdeskDims.sectionGap),
    ) {
        item {
            HomeToolbar(onRefresh) { controller.screen = Screen.SECURITY }
            Text("Xdesk", Modifier.padding(start = 4.dp, top = 8.dp), fontSize = 34.sp, fontWeight = FontWeight.Bold, lineHeight = 41.sp)
        }
        controller.identityError?.let { item { Text("$it. Vào Cài đặt để đặt lại danh tính.", color = MaterialTheme.colorScheme.error) } }
        controller.failure?.let { failure ->
            item { ConnectionErrorCard(failure, canRepair = controller.pairTarget != null, onRetry = controller::retry, onRepair = { controller.openPairing(controller.pairTarget) }, onDismiss = { controller.failure = null }) }
        }
        item {
            if (directory.paired.isEmpty()) EmptyPairingState { controller.openPairing(null) } else ScanQrRow { controller.openPairing(null) }
        }
        if (directory.paired.isNotEmpty()) {
            item {
                Group("Máy Mac của bạn") {
                    directory.paired.forEachIndexed { index, entry ->
                        if (index > 0) GroupDivider(XdeskDims.rowPad + XdeskDims.iconBox + XdeskDims.iconGap)
                        PairedHostRow(entry, { controller.connectPaired(entry) }, { forgetting = entry.known })
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
        item { SettingsSummaryRow(settingsSummary(controller.display.mode, controller.display.fit, pointerStore.settings.mode)) { controller.screen = Screen.SECURITY } }
        item {
            OtherConnectionsGroup(
                manual, { manual = it }, { controller.connectManual(manual) },
                canPair = ViewerTarget.parse(manual) != null, onPair = { controller.openPairing(ViewerTarget.parse(manual)) },
            )
        }
    }
    forgetting?.let { host ->
        ForgetHostDialog(host, { controller.forgetHost(host.id); forgetting = null }) { forgetting = null }
    }
}
