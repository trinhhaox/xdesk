package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.ui.theme.XdeskOverlay

private val PadShape = RoundedCornerShape(10.dp)
private val LabelMinHeight = 52.dp

/** Nút chữ lấp đầy ô cha (kích thước do bố cục quyết định, không ép min): phím tắt, số, bổ trợ dính. */
@Composable
internal fun KeyCapButton(
    title: String,
    modifier: Modifier = Modifier,
    active: Boolean = false,
    fontSize: Int = 14,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        modifier = modifier,
        shape = PadShape,
        color = if (active) XdeskOverlay.accent else XdeskOverlay.key,
        contentColor = XdeskOverlay.content,
    ) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(title, fontSize = fontSize.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, maxLines = 1, softWrap = false)
        }
    }
}

/** Nút có biểu tượng; đủ cao thì thêm nhãn ngắn dưới biểu tượng, thấp thì chỉ biểu tượng (nhãn thành mô tả truy cập). */
@Composable
internal fun IconPadButton(
    label: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    prominent: Boolean = false,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        modifier = modifier.semantics { contentDescription = label },
        shape = PadShape,
        color = if (prominent) XdeskOverlay.accent else XdeskOverlay.key,
        contentColor = XdeskOverlay.content,
    ) {
        BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            val showLabel = maxHeight >= LabelMinHeight
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Icon(icon, contentDescription = null, modifier = Modifier.size(if (prominent) 28.dp else 20.dp))
                if (showLabel) {
                    Text(label, fontSize = 11.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}
