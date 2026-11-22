package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.forgetHost
import vn.xox.xdesk.transport.KnownHost

/**
 * Trang "Bảo mật" (như SecuritySettingsView của iOS): "Thiết bị này" (dấu vân tay, đặt lại danh tính) và "Máy Mac đã ghép" với menu "…" để xoá máy.
 */
internal fun LazyListScope.securityPageItems(controller: ViewerController, onForget: (KnownHost) -> Unit, onReset: () -> Unit) {
    item {
        Group("Thiết bị này", footer = "Khoá riêng được bọc bằng Android Keystore và không nằm trong bản sao lưu.") {
            GroupRow {
                Column(Modifier.weight(1f)) {
                    Text("Dấu vân tay", fontSize = 17.sp)
                    Text(controller.fingerprint ?: (controller.identityError ?: "Không có"), fontSize = 13.sp, fontFamily = FontFamily.Monospace, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            GroupDivider()
            GroupRow(onReset) {
                Column(Modifier.weight(1f)) {
                    Text("Đặt lại danh tính", fontSize = 17.sp, color = MaterialTheme.colorScheme.error)
                    Text("Tạo khoá mới; các máy Mac đã ghép sẽ không nhận ra điện thoại này", fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
    item {
        Group("Máy Mac đã ghép") {
            if (controller.knownHosts.isEmpty()) GroupRow { Text("Chưa ghép với máy nào.", fontSize = 17.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            controller.knownHosts.forEachIndexed { index, host ->
                if (index > 0) GroupDivider()
                KnownHostRow(host) { onForget(host) }
            }
        }
    }
}

@Composable
private fun KnownHostRow(host: KnownHost, onForget: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    GroupRow {
        Column(Modifier.weight(1f)) {
            Text(host.name, fontSize = 17.sp)
            Text(host.id, fontSize = 12.sp, fontFamily = FontFamily.Monospace, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Box {
            IconButton({ menu = true }) { Icon(XdeskIcons.EllipsisCircle, contentDescription = "Tuỳ chọn cho ${host.name}", Modifier.size(26.dp), tint = MaterialTheme.colorScheme.primary) }
            DropdownMenu(menu, { menu = false }) {
                DropdownMenuItem(
                    { Text("Xoá máy này", color = MaterialTheme.colorScheme.error) }, { menu = false; onForget() },
                    leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
                )
            }
        }
    }
}

@Composable
internal fun ConfirmDialog(title: String, text: String, confirm: String, onConfirm: () -> Unit, destructive: Boolean = true, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss, title = { Text(title) }, text = { Text(text) },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(confirm, color = if (destructive) MaterialTheme.colorScheme.error else Color.Unspecified)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Huỷ") } },
    )
}
