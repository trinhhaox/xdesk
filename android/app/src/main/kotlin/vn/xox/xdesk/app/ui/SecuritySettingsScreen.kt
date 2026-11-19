package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import vn.xox.xdesk.app.Screen
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.update.UpdateController
import vn.xox.xdesk.transport.KnownHost

/** Bảo mật: dấu vân tay của thiết bị này, host đã ghép (quên từng host) và đặt lại danh tính. */
@Composable
fun SecuritySettingsScreen(controller: ViewerController, updates: UpdateController) {
    var confirmReset by remember { mutableStateOf(false) }
    var forgetting by remember { mutableStateOf<KnownHost?>(null) }
    LazyColumn(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { Text("Bảo mật", style = MaterialTheme.typography.headlineMedium) }
        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Dấu vân tay thiết bị này", style = MaterialTheme.typography.titleSmall)
                    Text(controller.fingerprint ?: (controller.identityError ?: "Không có"), fontFamily = FontFamily.Monospace)
                    Text("Khoá riêng được bọc bằng Android Keystore và không nằm trong bản sao lưu.", style = MaterialTheme.typography.bodySmall)
                }
            }
        }
        item { Text("Máy Mac đã ghép (${controller.knownHosts.size})", style = MaterialTheme.typography.titleMedium) }
        if (controller.knownHosts.isEmpty()) item { Text("Chưa ghép máy nào.") }
        items(controller.knownHosts, key = KnownHost::id) { host ->
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(host.name)
                    Text(host.id, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall)
                }
                TextButton(onClick = { forgetting = host }) { Text("Quên") }
            }
        }
        item { UpdateCard(updates) }
        item { Button(onClick = { confirmReset = true }) { Text("Đặt lại danh tính") } }
        item { OutlinedButton(onClick = { controller.screen = Screen.HOSTS }, modifier = Modifier.fillMaxWidth()) { Text("Quay lại") } }
    }
    forgetting?.let { host ->
        ConfirmDialog("Quên ${host.name}?", "Lần sau phải ghép đôi lại.", "Quên", { controller.forget(host.id); forgetting = null }) { forgetting = null }
    }
    if (confirmReset) {
        ConfirmDialog("Đặt lại danh tính?", "Tạo khoá mới; mọi máy Mac đã ghép sẽ không nhận ra điện thoại này nữa.", "Đặt lại",
            { controller.resetIdentity(); confirmReset = false }) { confirmReset = false }
    }
}

@Composable
private fun ConfirmDialog(title: String, text: String, confirm: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss, title = { Text(title) }, text = { Text(text) },
        confirmButton = { TextButton(onClick = onConfirm) { Text(confirm) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Huỷ") } },
    )
}
