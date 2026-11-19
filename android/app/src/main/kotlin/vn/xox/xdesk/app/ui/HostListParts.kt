package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import vn.xox.xdesk.app.discovery.HostBadge
import vn.xox.xdesk.app.discovery.PairedEntry
import vn.xox.xdesk.app.ui.theme.XdeskCard
import vn.xox.xdesk.app.ui.theme.extras
import vn.xox.xdesk.transport.KnownHost

/** Nút chính của màn chính: mở bộ quét QR ở màn Ghép đôi (quyền camera chỉ xin ở đó). Chưa ghép máy nào thì nổi bật hơn. */
@Composable
internal fun ScanQrButton(prominent: Boolean, onClick: () -> Unit) {
    val modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)
    val content: @Composable () -> Unit = {
        Icon(QrScanIcon, contentDescription = null)
        Text("Quét mã QR để ghép đôi", Modifier.padding(start = 8.dp))
    }
    if (prominent) Button(onClick, modifier) { content() } else FilledTonalButton(onClick, modifier) { content() }
}

/** Trạng thái rỗng khi chưa ghép máy nào: hướng dẫn trên Mac, mã 6 số là lựa chọn phụ. */
@Composable
internal fun EmptyPairedState(onSasPair: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Chưa ghép máy Mac nào.", style = MaterialTheme.typography.titleSmall)
        Text(
            "Trên Mac: menu Xdesk → Ghép đôi thiết bị mới… rồi quét mã QR hiện ra. Hoặc so mã 6 số, hay nhập địa chỉ ở cuối trang.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        OutlinedButton(onSasPair, Modifier.heightIn(min = 48.dp)) { Text("So mã 6 số") }
    }
}

/** Mac đã ghép: tên, trạng thái, nhãn "Đã ghép" và menu "Xoá máy này". */
@Composable
internal fun PairedHostRow(entry: PairedEntry, onConnect: () -> Unit, onForget: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    XdeskCard(Modifier.fillMaxWidth(), onConnect) {
        ListItem(
            headlineContent = { Text(entry.known.name) }, supportingContent = { Text(entry.status.label) },
            trailingContent = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    BadgeChip(HostBadge.PAIRED)
                    IconButton({ menu = true }, Modifier.padding(start = 4.dp)) {
                        Icon(Icons.Filled.MoreVert, contentDescription = "Tuỳ chọn cho ${entry.known.name}")
                    }
                    DropdownMenu(menu, { menu = false }) {
                        DropdownMenuItem(text = { Text("Xoá máy này", color = MaterialTheme.colorScheme.error) }, onClick = { menu = false; onForget() })
                    }
                }
            },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        )
    }
}

/** Mac chưa ghép (hoặc khoá đã đổi) thấy trên mạng. */
@Composable
internal fun OtherHostRow(name: String, address: String, badge: HostBadge, onClick: () -> Unit) {
    XdeskCard(Modifier.fillMaxWidth(), onClick) {
        ListItem(
            headlineContent = { Text(name) }, supportingContent = { Text(address) },
            trailingContent = { BadgeChip(badge) }, colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        )
    }
}

/** Nhãn trạng thái ghép: nền tonal có chữ tương phản ≥ 4.5:1 ở cả hai giao diện. */
@Composable
private fun BadgeChip(badge: HostBadge) {
    val (container, content) = when (badge) {
        HostBadge.PAIRED -> MaterialTheme.colorScheme.tertiaryContainer to MaterialTheme.colorScheme.onTertiaryContainer
        HostBadge.UNPAIRED -> MaterialTheme.colorScheme.secondaryContainer to MaterialTheme.colorScheme.onSecondaryContainer
        HostBadge.KEY_CHANGED -> MaterialTheme.extras.warningContainer to MaterialTheme.extras.onWarningContainer
    }
    Surface(color = container, contentColor = content, shape = RoundedCornerShape(50)) {
        Text(badge.label, Modifier.padding(horizontal = 12.dp, vertical = 6.dp), style = MaterialTheme.typography.labelLarge)
    }
}

/** Hộp xác nhận xoá một Mac đã ghép; dùng chung cho màn chính và Cài đặt. */
@Composable
internal fun ForgetHostDialog(host: KnownHost, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    ConfirmDialog(
        "Xoá ${host.name}?",
        "Điện thoại sẽ không tự kết nối tới máy này nữa. Muốn dùng lại phải ghép đôi lại. " +
            "(Trên Mac, thiết bị này vẫn có trong danh sách cho tới khi bạn thu hồi.)",
        "Xoá", onConfirm, onDismiss,
    )
}
