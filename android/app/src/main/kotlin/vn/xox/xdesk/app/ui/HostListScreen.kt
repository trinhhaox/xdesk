package vn.xox.xdesk.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import vn.xox.xdesk.app.PointerSettingsStore
import vn.xox.xdesk.app.Screen
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.discovery.HostBadge
import vn.xox.xdesk.transport.KnownHost
import vn.xox.xdesk.transport.ViewerTarget

/** Danh sách host: kết quả NSD (kèm nhãn Đã ghép / Chưa ghép / Khoá đã đổi), host đã ghép ngoại tuyến và nhập tay host:port. */
@Composable
fun HostListScreen(controller: ViewerController) {
    var manual by remember { mutableStateOf("") }
    val context = LocalContext.current
    val pointerStore = remember { PointerSettingsStore(context) }
    val trust = controller.trust
    LazyColumn(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text("Xdesk", style = MaterialTheme.typography.headlineMedium)
                TextButton(onClick = { controller.screen = Screen.SECURITY }) { Text("Bảo mật") }
            }
        }
        controller.identityError?.let { item { Text("$it. Vào Bảo mật để đặt lại danh tính.", color = MaterialTheme.colorScheme.error) } }
        controller.failure?.let { failure ->
            item {
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(failure.message, color = MaterialTheme.colorScheme.error)
                        if (failure.repairable && controller.pairTarget != null) {
                            Button(onClick = { controller.screen = Screen.PAIR }) { Text("Ghép đôi lại") }
                        }
                    }
                }
            }
        }
        item { DisplaySettingsCard(controller.display, pointerStore) }
        item { Text("Máy Mac trên mạng", style = MaterialTheme.typography.titleMedium) }
        if (controller.hosts.isEmpty()) item { Text("Chưa thấy máy nào. Bật Xdesk trên Mac cùng mạng Wi-Fi, hoặc nhập địa chỉ bên dưới.") }
        items(controller.hosts, key = { it.id + it.host }) { host ->
            val badge = trust?.let { HostBadge.of(host, it) } ?: HostBadge.UNPAIRED
            HostRow(host.name, "${host.host}:${host.port}", badge) {
                if (badge == HostBadge.PAIRED) controller.connect(host.toTarget()) else controller.openPairing(host.toTarget())
            }
        }
        val offline = controller.knownHosts.filter { known -> controller.hosts.none { it.id == known.id } && known.lastAddress != null }
        if (offline.isNotEmpty()) item { Text("Đã ghép (chưa thấy trên mạng)", style = MaterialTheme.typography.titleMedium) }
        items(offline, key = KnownHost::id) { known ->
            HostRow(known.name, known.lastAddress.orEmpty(), HostBadge.PAIRED) { ViewerTarget.parse(known.lastAddress.orEmpty())?.let(controller::connect) }
        }
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Nhập địa chỉ", style = MaterialTheme.typography.titleMedium)
                OutlinedTextField(manual, { manual = it }, Modifier.fillMaxWidth(), label = { Text("host:port, ví dụ 192.168.1.10:47800") }, singleLine = true)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { controller.connectManual(manual) }, enabled = manual.isNotBlank()) { Text("Kết nối") }
                    OutlinedButton(onClick = { controller.openPairing(ViewerTarget.parse(manual)) }) { Text("Ghép đôi") }
                }
            }
        }
    }
}

@Composable
private fun HostRow(name: String, address: String, badge: HostBadge, onClick: () -> Unit) {
    Card(Modifier.fillMaxWidth().clickable(onClick = onClick)) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(name, style = MaterialTheme.typography.titleSmall)
                Text(address, style = MaterialTheme.typography.bodySmall)
            }
            val warn = badge == HostBadge.KEY_CHANGED
            Text(badge.label, color = if (warn) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary)
        }
    }
}
