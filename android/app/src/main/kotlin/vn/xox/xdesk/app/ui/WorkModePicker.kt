package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.WorkMode
import vn.xox.xdesk.app.ui.theme.XdeskOverlay

internal fun WorkMode.icon(): ImageVector = when (this) {
    WorkMode.MIRROR -> XdeskIcons.Laptop
    WorkMode.EXTEND -> XdeskIcons.SecondDisplay
    WorkMode.TRACKPAD -> XdeskIcons.Mouse
    WorkMode.KEYBOARD -> XdeskIcons.Keyboard
    WorkMode.NUMPAD_MEDIA -> XdeskIcons.Presentation
}

/**
 * Bộ chọn nhanh 5 chế độ làm việc dạng lưới 2+3 gọn gàng:
 * - Hàng 1: Chiếu Mac | Màn phụ
 * - Hàng 2: Chuột | Bàn phím | Slide & Số
 */
@Composable
internal fun WorkModeSwitcher(
    activeMode: WorkMode,
    onSelectMode: (WorkMode) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            WorkModePill(WorkMode.MIRROR, activeMode == WorkMode.MIRROR, Modifier.weight(1f)) { onSelectMode(WorkMode.MIRROR) }
            WorkModePill(WorkMode.EXTEND, activeMode == WorkMode.EXTEND, Modifier.weight(1f)) { onSelectMode(WorkMode.EXTEND) }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            WorkModePill(WorkMode.TRACKPAD, activeMode == WorkMode.TRACKPAD, Modifier.weight(1f)) { onSelectMode(WorkMode.TRACKPAD) }
            WorkModePill(WorkMode.KEYBOARD, activeMode == WorkMode.KEYBOARD, Modifier.weight(1f)) { onSelectMode(WorkMode.KEYBOARD) }
            WorkModePill(WorkMode.NUMPAD_MEDIA, activeMode == WorkMode.NUMPAD_MEDIA, Modifier.weight(1f)) { onSelectMode(WorkMode.NUMPAD_MEDIA) }
        }
    }
}

@Composable
private fun WorkModePill(
    mode: WorkMode,
    selected: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        modifier = modifier.heightIn(min = 40.dp),
        shape = RoundedCornerShape(10.dp),
        color = if (selected) XdeskOverlay.accent else XdeskOverlay.key,
        contentColor = if (selected) Color.White else Color.White.copy(alpha = 0.85f),
    ) {
        Row(
            Modifier.padding(horizontal = 4.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(mode.icon(), contentDescription = null, Modifier.size(14.dp))
            Spacer(Modifier.width(3.dp))
            Text(
                mode.shortTitle,
                fontSize = 11.sp,
                fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                maxLines = 1,
                softWrap = false,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
