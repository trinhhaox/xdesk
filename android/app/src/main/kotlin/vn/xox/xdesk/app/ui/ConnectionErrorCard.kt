package vn.xox.xdesk.app.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.ui.theme.XdeskCard
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.IconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import vn.xox.xdesk.app.ConnectionFailure
import vn.xox.xdesk.app.describe
import vn.xox.xdesk.app.technicalDetail
import vn.xox.xdesk.app.ui.theme.extras

/**
 * Lỗi kết nối trong danh sách, dựng như ConnectionErrorCard của iOS: biểu tượng, câu giải thích, gợi ý, nút đóng ✕, nút chính toàn chiều rộng
 * ("Thử lại" hoặc "Ghép đôi" khi lỗi do ghép đôi) và "Chi tiết" mở ra câu kỹ thuật gốc. Khoá host đổi dùng màu cảnh báo thay vì màu lỗi.
 */
@Composable
fun ConnectionErrorCard(failure: ConnectionFailure, canRepair: Boolean, onRetry: () -> Unit, onRepair: () -> Unit, onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    val text = failure.describe()
    val tint = if (text.warning) MaterialTheme.extras.warning else MaterialTheme.colorScheme.error
    val detail = failure.technicalDetail()
    var showDetail by remember(failure) { mutableStateOf(false) }
    XdeskCard(modifier.fillMaxWidth().semantics { liveRegion = LiveRegionMode.Polite }) {
        Column(Modifier.padding(start = XdeskDims.rowPad, top = 12.dp, end = 4.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(Icons.Filled.Warning, contentDescription = null, Modifier.padding(top = 10.dp).size(24.dp), tint = tint)
                Column(Modifier.weight(1f).padding(top = 10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(text.title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                    Text(text.hint, fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                IconButton(onDismiss) { Icon(Icons.Filled.Close, contentDescription = "Đóng thông báo lỗi", tint = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            Column(Modifier.padding(end = XdeskDims.rowPad - 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (failure.repairable && canRepair) ActionButton("Ghép đôi", null, onRepair)
                else if (!failure.repairable && failure.code != null) ActionButton("Thử lại", Icons.Filled.Refresh, onRetry)
                if (detail != null) {
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable { showDetail = !showDetail }, verticalAlignment = Alignment.CenterVertically) {
                        Text("Chi tiết", Modifier.weight(1f), fontSize = 15.sp)
                        Icon(XdeskIcons.Chevron, contentDescription = if (showDetail) "Thu gọn" else "Mở rộng", Modifier.rotate(if (showDetail) 90f else 0f).size(14.dp), tint = MaterialTheme.extras.tertiaryLabel)
                    }
                    AnimatedVisibility(showDetail) { Text(detail, fontSize = 13.sp, fontFamily = FontFamily.Monospace, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
            }
        }
    }
}

@Composable
private fun ActionButton(label: String, icon: ImageVector?, onClick: () -> Unit) = Button(
    onClick, Modifier.fillMaxWidth().heightIn(min = 48.dp), shape = CircleShape,
    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.extras.primaryFill, contentColor = Color.White),
) {
    if (icon != null) Icon(icon, contentDescription = null, Modifier.size(18.dp))
    Text(label, Modifier.padding(start = if (icon != null) 8.dp else 0.dp), fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
}
