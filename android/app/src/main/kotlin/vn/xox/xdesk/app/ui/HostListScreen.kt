package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
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
import vn.xox.xdesk.app.ui.theme.XdeskCard
import vn.xox.xdesk.transport.KnownHost
import vn.xox.xdesk.transport.ViewerTarget

/**
 * Màn chính: nút quét QR, mọi Mac đã ghép ("Máy Mac của bạn", kể cả khi NSD không thấy), Mac chưa ghép thấy trên mạng,
 * tóm tắt cài đặt hiển thị và ô nhập địa chỉ. Cài đặt chi tiết ở màn Cài đặt.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HostListScreen(controller: ViewerController) {
    var manual by remember { mutableStateOf("") }
    var forgetting by remember { mutableStateOf<KnownHost?>(null) }
    val pointerStore = LocalContext.current.let { context -> remember { PointerSettingsStore(context) } }
    val trust = controller.trust
    val directory = controller.directory
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Xdesk") }, windowInsets = WindowInsets(0),
                actions = {
                    IconButton({ controller.screen = Screen.SECURITY }) { Icon(Icons.Filled.Settings, contentDescription = "Cài đặt") }
                },
            )
        },
        contentWindowInsets = WindowInsets(0), containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            controller.identityError?.let { item { Text("$it. Vào Cài đặt để đặt lại danh tính.", color = MaterialTheme.colorScheme.error) } }
            controller.failure?.let { failure ->
                item {
                    ConnectionErrorCard(failure, canRepair = controller.pairTarget != null, onRetry = controller::retry, onRepair = { controller.openPairing(controller.pairTarget) })
                }
            }
            item { ScanQrButton(prominent = directory.paired.isEmpty()) { controller.openPairing(null) } }
            item { Text("Máy Mac của bạn", style = MaterialTheme.typography.titleMedium) }
            if (directory.paired.isEmpty()) item { EmptyPairedState { controller.openPairing(null, startOnSas = true) } }
            items(directory.paired, key = { it.known.id }) { entry ->
                PairedHostRow(entry, { controller.connectPaired(entry) }, { forgetting = entry.known })
            }
            if (directory.others.isNotEmpty()) {
                item { Text("Máy Mac khác trên mạng", style = MaterialTheme.typography.titleMedium) }
                items(directory.others, key = { it.id + it.host }) { host ->
                    val badge = trust?.let { HostBadge.of(host, it) } ?: HostBadge.UNPAIRED
                    OtherHostRow(host.name, "${host.host}:${host.port}", badge) { controller.openPairing(host.toTarget()) }
                }
            }
            item { SettingsSummaryRow(settingsSummary(controller.display.mode, controller.display.fit, pointerStore.settings.mode)) { controller.screen = Screen.SECURITY } }
            item { ManualAddress(manual, { manual = it }, { controller.connectManual(manual) }, { controller.openPairing(ViewerTarget.parse(manual)) }) }
        }
    }
    forgetting?.let { host ->
        ForgetHostDialog(host, { controller.forgetHost(host.id); forgetting = null }) { forgetting = null }
    }
}

@Composable
private fun SettingsSummaryRow(summary: String, onClick: () -> Unit) {
    XdeskCard(Modifier.fillMaxWidth(), onClick) {
        ListItem(
            headlineContent = { Text("Hiển thị và chuột") }, supportingContent = { Text(summary) },
            trailingContent = { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null) },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        )
    }
}

@Composable
private fun ManualAddress(value: String, onChange: (String) -> Unit, onConnect: () -> Unit, onPair: () -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        OutlinedTextField(value, onChange, Modifier.weight(1f), label = { Text("Nhập địa chỉ host:port") }, singleLine = true)
        Button(onClick = onConnect, enabled = value.isNotBlank()) { Text("Kết nối") }
    }
    OutlinedButton(onClick = onPair, enabled = ViewerTarget.parse(value) != null) { Text("Ghép đôi bằng địa chỉ này") }
}
