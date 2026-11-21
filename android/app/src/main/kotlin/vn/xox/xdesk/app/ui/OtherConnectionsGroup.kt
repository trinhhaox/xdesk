package vn.xox.xdesk.app.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.ui.theme.extras

/** "Cách kết nối khác": "Nhập địa chỉ" và "Cáp USB", thu gọn mặc định và mở ngay tại chỗ (như DisclosureGroup của iOS). */
@Composable
internal fun OtherConnectionsGroup(address: String, onAddressChange: (String) -> Unit, onConnect: () -> Unit, canPair: Boolean, onPair: () -> Unit) {
    var addressOpen by rememberSaveable { mutableStateOf(false) }
    var usbOpen by rememberSaveable { mutableStateOf(false) }
    Group("Cách kết nối khác") {
        DisclosureRow(XdeskIcons.Globe, "Nhập địa chỉ", addressOpen) { addressOpen = !addressOpen }
        AnimatedVisibility(addressOpen) {
            Column(Modifier.padding(horizontal = XdeskDims.rowPad, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(address, onAddressChange, Modifier.fillMaxWidth(), label = { Text("192.168.1.10:47800 hoặc 100.x.y.z") }, singleLine = true)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Button(
                        onConnect, Modifier.heightIn(min = 48.dp), enabled = address.isNotBlank(),
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.extras.primaryFill, contentColor = Color.White),
                    ) { Text("Kết nối") }
                    OutlinedButton(onPair, Modifier.heightIn(min = 48.dp), enabled = canPair) { Text("Ghép đôi") }
                }
                Text(
                    "Qua Tailscale: nhập IP 100.x.y.z hoặc tên máy (MagicDNS) của Mac. Trên Mac phải bật \"Cho phép kết nối qua Tailscale\".",
                    fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        GroupDivider(XdeskDims.rowPad + XdeskDims.iconBox + XdeskDims.iconGap)
        DisclosureRow(XdeskIcons.Cable, "Cáp USB", usbOpen) { usbOpen = !usbOpen }
        AnimatedVisibility(usbOpen) {
            Column(Modifier.padding(horizontal = XdeskDims.rowPad, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "Cắm cáp USB vào Mac (đã bật USB Debugging). Cổng 47800 sẽ đi thẳng qua cáp USB độ trễ siêu thấp.",
                    fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(
                    onClick = {
                        onAddressChange("127.0.0.1:47800")
                        onConnect()
                    },
                    modifier = Modifier.heightIn(min = 44.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.extras.primaryFill, contentColor = Color.White),
                ) {
                    Text("Nối cáp USB (127.0.0.1:47800)")
                }
            }
        }
    }
}

/** Hàng mở rộng: mũi tên màu chữ chính (đậm như DisclosureGroup), xoay xuống khi mở; đọc là "đã mở/đã thu gọn" bằng nhãn. */
@Composable
private fun DisclosureRow(icon: ImageVector, title: String, open: Boolean, onToggle: () -> Unit) = GroupRow(onToggle) {
    RowIcon(icon)
    Text(title, Modifier.weight(1f).padding(start = XdeskDims.iconGap), fontSize = 17.sp)
    Icon(
        XdeskIcons.Chevron, contentDescription = if (open) "Thu gọn" else "Mở rộng",
        Modifier.rotate(if (open) 90f else 0f).padding(2.dp), tint = MaterialTheme.colorScheme.onSurface,
    )
}
