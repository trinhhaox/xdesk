package vn.xox.xdesk.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.ui.theme.XdeskCard
import vn.xox.xdesk.app.ui.theme.extras

/** Số đo dùng chung của các màn danh sách/cài đặt, theo docs/design-tokens.md. */
internal object XdeskDims {
    val gutter = 18.dp
    val rowPad = 20.dp
    val rowMin = 52.dp
    val iconBox = 28.dp
    val iconGap = 12.dp
    val sectionGap = 28.dp
}

/** Tiêu đề nhóm: chữ 17 đậm màu phụ, thụt 18 so với thẻ. */
@Composable
internal fun GroupHeader(text: String, modifier: Modifier = Modifier) =
    Text(text, modifier.padding(start = XdeskDims.gutter), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)

/** Chú thích dưới nhóm: chữ 13 màu phụ. */
@Composable
internal fun GroupFooter(text: String, modifier: Modifier = Modifier) =
    Text(text, modifier.padding(horizontal = XdeskDims.gutter), color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 13.sp, lineHeight = 18.sp)

/** Đường kẻ giữa hàng; `indent` là phần thụt từ mép thẻ (bắt đầu từ chữ khi hàng có biểu tượng). */
@Composable
internal fun GroupDivider(indent: Dp = XdeskDims.rowPad) =
    HorizontalDivider(Modifier.padding(start = indent, end = XdeskDims.rowPad), color = MaterialTheme.colorScheme.outlineVariant)

/** Một hàng trong thẻ: cao tối thiểu 52 (đích chạm ≥ 48), đệm ngang 20; có `onClick` thì cả hàng bấm được. */
@Composable
internal fun GroupRow(onClick: (() -> Unit)? = null, content: @Composable RowScope.() -> Unit) = Row(
    Modifier.fillMaxWidth().heightIn(min = XdeskDims.rowMin).let { if (onClick != null) it.clickable(onClick = onClick) else it }
        .padding(horizontal = XdeskDims.rowPad, vertical = 8.dp),
    verticalAlignment = Alignment.CenterVertically, content = content,
)

@Composable
internal fun RowIcon(icon: ImageVector, tint: Color = MaterialTheme.colorScheme.primary) =
    Icon(icon, contentDescription = null, Modifier.size(XdeskDims.iconBox).padding(1.dp), tint = tint)

@Composable
internal fun ChevronIcon(tint: Color = MaterialTheme.extras.tertiaryLabel, size: Dp = 16.dp) =
    Icon(XdeskIcons.Chevron, contentDescription = null, Modifier.size(size), tint = tint)

/** Tiêu đề hàng 17 + dòng phụ 15 (màu phụ) theo chiều dọc. */
@Composable
internal fun RowScope.TitleAndSubtitle(title: String, subtitle: String?, modifier: Modifier = Modifier, subtitleColor: Color = MaterialTheme.colorScheme.onSurfaceVariant) =
    Column(modifier.weight(1f)) {
        Text(title, fontSize = 17.sp, lineHeight = 22.sp, color = MaterialTheme.colorScheme.onSurface)
        if (subtitle != null) Text(subtitle, fontSize = 15.sp, lineHeight = 20.sp, color = subtitleColor)
    }

/** Hàng "Tiêu đề … giá trị ›" (Điều khiển, Bảo mật). */
@Composable
internal fun ValueRow(title: String, value: String, onClick: () -> Unit) = GroupRow(onClick) {
    Text(title, Modifier.weight(1f), fontSize = 17.sp, color = MaterialTheme.colorScheme.onSurface)
    Text(value, fontSize = 17.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(end = 8.dp))
    ChevronIcon()
}

/** Nhóm có tiêu đề (tuỳ chọn), thẻ và chú thích (tuỳ chọn). */
@Composable
internal fun Group(header: String? = null, footer: String? = null, content: @Composable ColumnScope.() -> Unit) =
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (header != null) GroupHeader(header)
        XdeskCard(Modifier.fillMaxWidth(), content = content)
        if (footer != null) GroupFooter(footer)
    }

/** Màn cài đặt con: nút quay lại tròn bên trái, tiêu đề giữa (17 đậm) như thanh điều hướng iOS, rồi danh sách các nhóm. */
@Composable
internal fun SettingsScaffold(title: String, onBack: () -> Unit, content: LazyListScope.() -> Unit) = Column(Modifier.fillMaxSize()) {
    Box(Modifier.fillMaxWidth().padding(horizontal = XdeskDims.gutter, vertical = 8.dp), contentAlignment = Alignment.Center) {
        Surface(Modifier.align(Alignment.CenterStart), shape = CircleShape, color = MaterialTheme.extras.toolbarPill) {
            IconButton(onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Quay lại") }
        }
        Text(title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
    }
    LazyColumn(
        Modifier.fillMaxSize(), contentPadding = PaddingValues(start = XdeskDims.gutter, end = XdeskDims.gutter, top = 8.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(XdeskDims.sectionGap), content = content,
    )
}
