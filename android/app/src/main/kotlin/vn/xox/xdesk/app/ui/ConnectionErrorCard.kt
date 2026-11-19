package vn.xox.xdesk.app.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
 * Lỗi kết nối nằm trong danh sách: biểu tượng, câu giải thích dễ hiểu, gợi ý khắc phục, nút "Thử lại" (hoặc "Ghép đôi lại" khi lỗi do ghép đôi)
 * và "Chi tiết" mở ra câu kỹ thuật gốc. Khoá host đổi dùng màu cảnh báo thay vì màu lỗi vì đó là cảnh báo bảo mật, không phải sự cố mạng.
 */
@Composable
fun ConnectionErrorCard(failure: ConnectionFailure, canRepair: Boolean, onRetry: () -> Unit, onRepair: () -> Unit, modifier: Modifier = Modifier) {
    val text = failure.describe()
    val container = if (text.warning) MaterialTheme.extras.warningContainer else MaterialTheme.colorScheme.errorContainer
    val content = if (text.warning) MaterialTheme.extras.onWarningContainer else MaterialTheme.colorScheme.onErrorContainer
    val detail = failure.technicalDetail()
    var showDetail by remember(failure) { mutableStateOf(false) }
    Card(
        modifier.fillMaxWidth().semantics { liveRegion = LiveRegionMode.Polite },
        colors = CardDefaults.cardColors(containerColor = container, contentColor = content),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(Icons.Filled.Warning, contentDescription = null, Modifier.size(24.dp))
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(text.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text(text.hint, style = MaterialTheme.typography.bodyMedium)
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (failure.repairable) {
                    if (canRepair) Button(onClick = onRepair) { Text("Ghép đôi lại") }
                } else if (failure.code != null) {
                    Button(onClick = onRetry) {
                        Icon(Icons.Filled.Refresh, contentDescription = null, Modifier.size(18.dp))
                        Text("Thử lại", Modifier.padding(start = 8.dp))
                    }
                }
                if (detail != null) {
                    TextButton({ showDetail = !showDetail }, colors = ButtonDefaults.textButtonColors(contentColor = content)) {
                        Text("Chi tiết")
                        Icon(if (showDetail) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown, contentDescription = if (showDetail) "Thu gọn" else "Mở rộng")
                    }
                }
            }
            if (detail != null) {
                AnimatedVisibility(showDetail) { Text(detail, style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace) }
            }
        }
    }
}
