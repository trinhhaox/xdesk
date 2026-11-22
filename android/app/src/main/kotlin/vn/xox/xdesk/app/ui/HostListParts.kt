package vn.xox.xdesk.app.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.discovery.HostBadge
import vn.xox.xdesk.app.discovery.HostStatus
import vn.xox.xdesk.app.discovery.PairedEntry
import vn.xox.xdesk.app.ui.theme.extras
import vn.xox.xdesk.transport.KnownHost

/** Viên thuốc góc phải trên cùng chứa "Tìm lại", "+" (khi đã có máy) và "Cài đặt". */
@Composable
internal fun HomeToolbar(onRefresh: () -> Unit, onSettings: () -> Unit, onAdd: (() -> Unit)? = null) =
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
        Surface(shape = CircleShape, color = MaterialTheme.extras.toolbarPill, border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f))) {
            Row(Modifier.padding(horizontal = 4.dp)) {
                IconButton(onRefresh) { Icon(Icons.Filled.Refresh, contentDescription = "Tìm lại", tint = MaterialTheme.colorScheme.primary) }
                if (onAdd != null) {
                    IconButton(onAdd) { Icon(Icons.Filled.Add, contentDescription = "Thêm máy Mac", tint = MaterialTheme.colorScheme.primary) }
                }
                IconButton(onSettings) { Icon(Icons.Outlined.Settings, contentDescription = "Cài đặt", tint = MaterialTheme.colorScheme.primary) }
            }
        }
    }

@Composable
internal fun ScanQrButton(onClick: () -> Unit) = Surface(onClick, Modifier.fillMaxWidth().heightIn(min = 64.dp), shape = CircleShape, color = MaterialTheme.extras.primaryFill, contentColor = Color.White) {
    Row(Modifier.padding(horizontal = 20.dp), Arrangement.Center, Alignment.CenterVertically) {
        Icon(QrScanIcon, contentDescription = null, Modifier.size(26.dp))
        Text("Quét mã QR để ghép đôi", Modifier.padding(start = 12.dp), fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
    }
}

/** Màn trống khi chưa ghép máy nào: quét QR là hành động chính; mã 6 số hoặc nhập địa chỉ là đường phụ. */
@Composable
internal fun EmptyPairingState(onScan: () -> Unit) = Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
    Icon(XdeskIcons.Monitor, contentDescription = null, Modifier.size(44.dp), tint = MaterialTheme.colorScheme.primary)
    Text("Chưa ghép với máy Mac nào", fontSize = 20.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
    Text("Trên Mac: menu Xdesk → Ghép đôi thiết bị mới…, rồi quét mã QR hiện trên Mac.", fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
    ScanQrButton(onScan)
    Text(
        "Không quét được? Chọn một máy Mac trong mục \"Máy Mac khác trên mạng\" để so mã 6 số, hoặc nhập địa chỉ ở \"Cách kết nối khác\".",
        fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center,
    )
}

/** Mac đã ghép: biểu tượng máy, tên, trạng thái mạng, nút chuyển nhanh Chuột/Màn hình và menu "…" (Xoá máy này). */
@Composable
internal fun PairedHostRow(
    entry: PairedEntry,
    secondaryIsVideo: Boolean,
    onConnect: () -> Unit,
    onSecondaryAction: () -> Unit,
    onForget: () -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    val offline = entry.status == HostStatus.NotSeen
    Row(
        Modifier.fillMaxWidth().heightIn(min = 72.dp).clickable(onClick = onConnect).padding(start = XdeskDims.rowPad, end = 4.dp, top = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RowIcon(XdeskIcons.Monitor, if (offline) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.primary)
        Column(Modifier.weight(1f).padding(start = XdeskDims.iconGap, end = 4.dp)) {
            Text(entry.known.name, fontSize = 17.sp, lineHeight = 22.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(
                entry.status.label, fontSize = 14.sp, lineHeight = 19.sp, maxLines = 2, overflow = TextOverflow.Ellipsis,
                color = if (entry.status == HostStatus.Ready) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        IconButton(onSecondaryAction) {
            Icon(
                if (secondaryIsVideo) XdeskIcons.Laptop else XdeskIcons.Mouse,
                contentDescription = if (secondaryIsVideo) "Chiếu màn hình Mac cho ${entry.known.name}" else "Chuột cảm ứng cho ${entry.known.name}",
                Modifier.size(24.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
        }
        Box {
            IconButton({ menu = true }) { Icon(XdeskIcons.EllipsisCircle, contentDescription = "Tuỳ chọn cho ${entry.known.name}", Modifier.size(26.dp), tint = MaterialTheme.colorScheme.primary) }
            DropdownMenu(menu, { menu = false }) {
                DropdownMenuItem(
                    { Text("Xoá máy này", color = MaterialTheme.colorScheme.error) }, { menu = false; onForget() },
                    leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
                )
            }
        }
    }
}

/** Mac chưa ghép (hoặc khoá đã đổi) thấy trên mạng. */
@Composable
internal fun OtherHostRow(name: String, address: String, badge: HostBadge, onClick: () -> Unit) = GroupRow(onClick) {
    RowIcon(XdeskIcons.Monitor)
    TitleAndSubtitle(name, address, Modifier.padding(start = XdeskDims.iconGap))
    BadgeText(badge, Modifier.padding(horizontal = 8.dp))
    ChevronIcon()
}

/** Nhãn trạng thái ghép: chữ đậm 13, màu theo trạng thái (accent / cảnh báo / lỗi). */
@Composable
private fun BadgeText(badge: HostBadge, modifier: Modifier = Modifier) {
    val color = when (badge) {
        HostBadge.PAIRED -> MaterialTheme.colorScheme.tertiary
        HostBadge.UNPAIRED -> MaterialTheme.extras.warning
        HostBadge.KEY_CHANGED -> MaterialTheme.colorScheme.error
    }
    Text(badge.label, modifier, color = color, fontSize = 13.sp, fontWeight = FontWeight.Bold)
}

/** Hộp xác nhận xoá một Mac đã ghép; dùng chung cho màn chính và Cài đặt. */
@Composable
internal fun ForgetHostDialog(host: KnownHost, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    ConfirmDialog(
        "Xoá ${host.name}?",
        "Điện thoại sẽ không tự kết nối tới máy này nữa. Muốn dùng lại phải ghép đôi lại. " +
            "(Trên Mac, thiết bị này vẫn có trong danh sách cho tới khi bạn thu hồi.)",
        "Xoá", onConfirm = onConfirm, destructive = true, onDismiss = onDismiss,
    )
}
