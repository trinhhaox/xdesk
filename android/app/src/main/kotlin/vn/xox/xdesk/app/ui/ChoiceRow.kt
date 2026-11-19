package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Phần thụt của đường kẻ giữa các [ChoiceRow]: bắt đầu từ chữ tiêu đề (sau biểu tượng). */
internal val ChoiceDividerIndent = XdeskDims.rowPad + XdeskDims.iconBox + XdeskDims.iconGap

/**
 * Hàng chọn một (radio) kiểu iOS: biểu tượng + tiêu đề, mô tả hai dòng bên dưới bắt đầu từ mép hàng, dấu ✓ xanh ở cuối khi đang chọn.
 * Cả hàng là vùng chọn (vai trò radio) nên TalkBack đọc "đã chọn".
 */
@Composable
internal fun ChoiceRow(icon: ImageVector, title: String, summary: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 64.dp).selectable(selected, onClick = onClick, role = Role.RadioButton)
            .padding(start = XdeskDims.rowPad, end = 12.dp, top = 12.dp, bottom = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f).padding(end = 28.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, contentDescription = null, Modifier.size(XdeskDims.iconBox).padding(1.dp), tint = MaterialTheme.colorScheme.primary)
                Text(title, Modifier.padding(start = XdeskDims.iconGap), fontSize = 17.sp)
            }
            Text(summary, Modifier.padding(top = 2.dp), fontSize = 15.sp, lineHeight = 21.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Box(Modifier.size(28.dp), contentAlignment = Alignment.Center) {
            if (selected) Icon(Icons.Filled.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        }
    }
}
