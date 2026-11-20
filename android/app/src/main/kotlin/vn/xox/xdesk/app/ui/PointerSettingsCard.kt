package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.util.Locale
import vn.xox.xdesk.app.PointerSettingsStore
import vn.xox.xdesk.app.input.PointerMode
import vn.xox.xdesk.app.input.PointerSettings

fun PointerMode.title() = if (this == PointerMode.DIRECT) "Chạm trực tiếp" else "Con trỏ"

/**
 * Nội dung "Chuột và con trỏ" (ba nhóm như PointerSettingsForm của iOS): chế độ + mô tả, "Tốc độ con trỏ", công tắc cuộn tự nhiên / nhấn giữ.
 * Dùng trong màn Cài đặt và trong hộp thoại ở màn stream.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PointerSettingsGroups(store: PointerSettingsStore, modifier: Modifier = Modifier) {
    val s = store.settings
    Column(modifier, verticalArrangement = Arrangement.spacedBy(XdeskDims.sectionGap)) {
        Group {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SegmentedPicker(PointerMode.entries.map { it to it.title() }, s.mode) { mode -> store.update { it.copy(mode = mode) } }
                Text(
                    if (s.mode == PointerMode.DIRECT) "Chạm đâu click đó, chạm 2 lần vào ô cần gõ để mở bàn phím. Vuốt một ngón để cuộn lên xuống (hất mạnh để trang trôi nhanh), nhấn giữ rồi kéo để kéo thả, nhấn giữ rồi nhả để chuột phải."
                    else "Trượt một ngón để di chuyển con trỏ, chạm để click. Hai ngón chạm = chuột phải, hai ngón trượt = cuộn, chạm rồi chạm-giữ-trượt = kéo.",
                    Modifier.padding(horizontal = 8.dp), fontSize = 14.sp, lineHeight = 20.sp, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Group("Tốc độ con trỏ") {
            val interaction = remember { MutableInteractionSource() }
            val speedText = "${"%.1f".format(Locale.US, s.safeSpeed)}×"
            Row(Modifier.padding(horizontal = XdeskDims.rowPad, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Slider(
                    value = s.safeSpeed, onValueChange = { v -> store.update { it.copy(speed = v) } }, valueRange = PointerSettings.SPEED_RANGE,
                    enabled = s.mode == PointerMode.TRACKPAD, modifier = Modifier.weight(1f).semantics { contentDescription = "Tốc độ con trỏ, $speedText" },
                    interactionSource = interaction, thumb = { SliderDefaults.Thumb(interaction, thumbSize = DpSize(24.dp, 24.dp), enabled = s.mode == PointerMode.TRACKPAD) },
                )
                Text(speedText, Modifier.width(52.dp), fontSize = 15.sp, fontFamily = FontFamily.Monospace, textAlign = TextAlign.End)
            }
            if (s.mode != PointerMode.TRACKPAD) {
                Text("Chỉ dùng ở chế độ Con trỏ.", Modifier.padding(start = XdeskDims.rowPad, end = XdeskDims.rowPad, bottom = 12.dp), fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Group(
            footer = "Cuộn tự nhiên: nội dung đi theo ngón tay. Hai ngón chạm cùng lúc luôn là chuột phải. " +
                "Chạm 2 lần để mở bàn phím thay cho double-click; tắt đi để chạm 2 lần là double-click.",
        ) {
            SwitchRow("Cuộn tự nhiên", s.naturalScroll) { v -> store.update { it.copy(naturalScroll = v) } }
            GroupDivider()
            SwitchRow("Nhấn giữ để chuột phải", s.longPressRightClick) { v -> store.update { it.copy(longPressRightClick = v) } }
            if (s.mode == PointerMode.DIRECT) {
                GroupDivider()
                SwitchRow("Chạm 2 lần để mở bàn phím", s.doubleTapOpensKeyboard) { v -> store.update { it.copy(doubleTapOpensKeyboard = v) } }
            }
        }
    }
}

/** Cả hàng là vùng bật/tắt (vai trò Switch) nên TalkBack đọc "Công tắc, bật/tắt" một lần, và vùng chạm ≥ 48 dp. */
@Composable
private fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = XdeskDims.rowMin).toggleable(checked, role = Role.Switch, onValueChange = onChange).padding(horizontal = XdeskDims.rowPad),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, Modifier.weight(1f), fontSize = 17.sp)
        Switch(checked = checked, onCheckedChange = null, colors = SwitchDefaults.colors(checkedTrackColor = MaterialTheme.colorScheme.tertiary, checkedThumbColor = Color.White))
    }
}
