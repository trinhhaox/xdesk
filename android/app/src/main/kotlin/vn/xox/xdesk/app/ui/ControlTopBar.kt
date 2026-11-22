package vn.xox.xdesk.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.KeyboardStyle
import vn.xox.xdesk.app.WorkMode
import vn.xox.xdesk.app.ui.theme.XdeskOverlay

private val PortraitBarHeight = 48.dp
private val LandscapeBarHeight = 36.dp

/**
 * Thanh trên một hàng cho cả 3 chế độ điều khiển: tên Mac | menu chọn chế độ | (nút gạt kiểu bàn phím) | Khoá | Ngắt.
 * Cao 48 dp dọc, 36 dp ngang.
 */
@Composable
internal fun ControlTopBar(
    targetName: String,
    activeMode: WorkMode,
    onSelectMode: (WorkMode) -> Unit,
    landscape: Boolean,
    keyboardStyle: KeyboardStyle?,
    onSelectKeyboardStyle: (KeyboardStyle) -> Unit,
    onLock: () -> Unit,
    onDisconnect: () -> Unit,
) {
    val barHeight = if (landscape) LandscapeBarHeight else PortraitBarHeight
    Row(
        Modifier.fillMaxWidth().height(barHeight).padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            targetName.ifBlank { "Điều khiển Mac" },
            modifier = Modifier.weight(1f).padding(start = 4.dp),
            maxLines = 1, overflow = TextOverflow.Ellipsis,
            color = XdeskOverlay.content, fontSize = if (landscape) 14.sp else 16.sp, fontWeight = FontWeight.SemiBold,
        )
        ModeMenu(activeMode, onSelectMode, barHeight - 8.dp)
        if (keyboardStyle != null) KeyboardStyleToggle(keyboardStyle, onSelectKeyboardStyle, barHeight - 8.dp)
        BarIconButton(XdeskIcons.Lock, "Khóa Mac", XdeskOverlay.content, barHeight, onLock)
        BarIconButton(XdeskIcons.Stop, "Ngắt kết nối", XdeskOverlay.danger, barHeight, onDisconnect)
    }
}

@Composable
private fun BarIconButton(icon: androidx.compose.ui.graphics.vector.ImageVector, description: String, tint: Color, size: androidx.compose.ui.unit.Dp, onClick: () -> Unit) {
    IconButton(onClick = onClick, modifier = Modifier.size(size)) {
        Icon(icon, contentDescription = description, tint = tint, modifier = Modifier.size(20.dp))
    }
}

@Composable
private fun ModeMenu(activeMode: WorkMode, onSelectMode: (WorkMode) -> Unit, height: androidx.compose.ui.unit.Dp) {
    var open by remember { mutableStateOf(false) }
    Box {
        Surface(
            onClick = { open = true },
            modifier = Modifier.height(height).semantics { contentDescription = "Chế độ: ${activeMode.title}" },
            shape = RoundedCornerShape(10.dp),
            color = XdeskOverlay.key,
            contentColor = XdeskOverlay.content,
        ) {
            Row(Modifier.padding(horizontal = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(activeMode.icon(), contentDescription = null, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(5.dp))
                Text(activeMode.shortTitle, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, softWrap = false)
                Text(" ▾", fontSize = 12.sp, color = XdeskOverlay.contentMuted)
            }
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, containerColor = XdeskOverlay.bar) {
            WorkMode.entries.forEach { mode ->
                DropdownMenuItem(
                    text = { Text(mode.title, fontSize = 14.sp, fontWeight = if (mode == activeMode) FontWeight.Bold else FontWeight.Normal, color = XdeskOverlay.content) },
                    leadingIcon = { Icon(mode.icon(), contentDescription = null, tint = if (mode == activeMode) XdeskOverlay.accentLight else XdeskOverlay.content, modifier = Modifier.size(18.dp)) },
                    onClick = { open = false; onSelectMode(mode) },
                )
            }
        }
    }
}

/** Nút gạt nhỏ: ⌨ = Bàn phím Mac, Aa = Gõ văn bản. */
@Composable
private fun KeyboardStyleToggle(style: KeyboardStyle, onSelect: (KeyboardStyle) -> Unit, height: androidx.compose.ui.unit.Dp) {
    Row(Modifier.height(height).background(XdeskOverlay.key, RoundedCornerShape(10.dp)).padding(2.dp)) {
        KeyboardStyle.entries.forEach { option ->
            Surface(
                onClick = { onSelect(option) },
                modifier = Modifier.height(height - 4.dp).width(34.dp).semantics { contentDescription = option.title },
                shape = RoundedCornerShape(8.dp),
                color = if (option == style) XdeskOverlay.accent else Color.Transparent,
                contentColor = XdeskOverlay.content,
            ) {
                Box(contentAlignment = Alignment.Center) {
                    if (option == KeyboardStyle.MAC) Icon(XdeskIcons.Keyboard, contentDescription = null, modifier = Modifier.size(18.dp))
                    else Text("Aa", fontSize = 13.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}
