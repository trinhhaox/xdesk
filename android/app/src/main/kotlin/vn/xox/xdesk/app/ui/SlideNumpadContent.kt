package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.RowScope
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import vn.xox.xdesk.app.input.HidKeys
import vn.xox.xdesk.app.input.NumpadLayout
import vn.xox.xdesk.transport.InputModifiers
import vn.xox.xdesk.wire.MediaKeyKind

private val Gap = 8.dp
private val FullPadding = 10.dp

/** Callback chung của chế độ "Slide & Số": phím thường + bổ trợ, phím media, phím số (HID keypad). */
internal class SlideNumpadActions(
    val onKey: (usage: Int, mods: Int) -> Unit,
    val onMediaKey: (MediaKeyKind) -> Unit,
)

/**
 * Slide & Số, không cuộn, lấp đầy vùng còn lại.
 * Dọc: Trình chiếu → Media → Bàn phím số xếp dọc. Ngang: 3 cột Trình chiếu | Media | Bàn phím số.
 */
@Composable
internal fun SlideNumpadContent(actions: SlideNumpadActions, landscape: Boolean, modifier: Modifier = Modifier) {
    if (landscape) {
        Row(modifier.fillMaxSize().padding(FullPadding), horizontalArrangement = Arrangement.spacedBy(Gap)) {
            Column(Modifier.weight(0.35f).fillMaxSize(), verticalArrangement = Arrangement.spacedBy(Gap)) { PresentationGroup(actions, landscape = true) }
            Column(Modifier.weight(0.2f).fillMaxSize(), verticalArrangement = Arrangement.spacedBy(Gap)) { MediaGroup(actions, columns = 2) }
            Column(Modifier.weight(0.45f).fillMaxSize(), verticalArrangement = Arrangement.spacedBy(Gap)) { NumpadGroup(actions) }
        }
    } else {
        Column(modifier.fillMaxSize().padding(FullPadding), verticalArrangement = Arrangement.spacedBy(Gap)) {
            PresentationGroup(actions, landscape = false)
            MediaGroup(actions, columns = 6, rowHeight = 48.dp)
            NumpadGroup(actions)
        }
    }
}

@Composable
private fun PadRow(modifier: Modifier, content: @Composable RowScope.() -> Unit) =
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Gap), content = content)

@Composable
private fun ColumnScope.PresentationGroup(actions: SlideNumpadActions, landscape: Boolean) {
    val big = if (landscape) Modifier.weight(2f) else Modifier.height(72.dp)
    val small = if (landscape) Modifier.weight(1f) else Modifier.height(44.dp)
    PadRow(big) {
        IconPadButton("Slide trước", XdeskIcons.ChevronLeftCircle, Modifier.weight(1f).fillMaxSize()) { actions.onKey(HidKeys.PAGE_UP, 0) }
        IconPadButton("Slide kế", XdeskIcons.ChevronRightCircle, Modifier.weight(1.4f).fillMaxSize(), prominent = true) { actions.onKey(HidKeys.PAGE_DOWN, 0) }
    }
    val extras = listOf<Triple<String, ImageVector, () -> Unit>>(
        Triple("Bắt đầu (F5)", XdeskIcons.Presentation) { actions.onKey(HidKeys.F5, 0) },
        Triple("Kết thúc (Esc)", XdeskIcons.ExitSlide) { actions.onKey(HidKeys.ESCAPE, 0) },
        Triple("Space", XdeskIcons.SpaceBar) { actions.onKey(HidKeys.SPACE, 0) },
        Triple("Hoàn tác (⌘Z)", XdeskIcons.Undo) { actions.onKey(HidKeys.Z, InputModifiers.COMMAND) },
    )
    val perRow = if (landscape) 2 else 4
    extras.chunked(perRow).forEach { chunk ->
        PadRow(small) {
            chunk.forEach { (label, icon, onClick) -> IconPadButton(label, icon, Modifier.weight(1f).fillMaxSize(), onClick = onClick) }
        }
    }
}

@Composable
private fun ColumnScope.MediaGroup(actions: SlideNumpadActions, columns: Int, rowHeight: Dp? = null) {
    val media = listOf(
        Triple("Bài trước", XdeskIcons.SkipPrevious, MediaKeyKind.PREVIOUS),
        Triple("Phát / Dừng", XdeskIcons.PlayPause, MediaKeyKind.PLAY_PAUSE),
        Triple("Bài kế", XdeskIcons.SkipNext, MediaKeyKind.NEXT),
        Triple("Tắt tiếng", XdeskIcons.VolumeOff, MediaKeyKind.MUTE),
        Triple("Giảm âm", XdeskIcons.VolumeDown, MediaKeyKind.VOLUME_DOWN),
        Triple("Tăng âm", XdeskIcons.VolumeUp, MediaKeyKind.VOLUME_UP),
    )
    media.chunked(columns).forEach { chunk ->
        PadRow(if (rowHeight != null) Modifier.height(rowHeight) else Modifier.weight(1f)) {
            chunk.forEach { (label, icon, kind) -> IconPadButton(label, icon, Modifier.weight(1f).fillMaxSize()) { actions.onMediaKey(kind) } }
        }
    }
}

@Composable
private fun ColumnScope.NumpadGroup(actions: SlideNumpadActions) {
    (NumpadLayout.rows + listOf(NumpadLayout.bottomRow)).forEach { row ->
        PadRow(Modifier.weight(1f)) {
            row.forEach { key ->
                KeyCapButton(key.label, Modifier.weight(1f).fillMaxSize(), fontSize = 18) { actions.onKey(key.usage, 0) }
            }
        }
    }
}
