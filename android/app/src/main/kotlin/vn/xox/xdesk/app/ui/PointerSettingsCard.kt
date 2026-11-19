package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import vn.xox.xdesk.app.PointerSettingsStore
import vn.xox.xdesk.app.input.PointerMode
import vn.xox.xdesk.app.input.PointerSettings

fun PointerMode.title() = if (this == PointerMode.DIRECT) "Chạm trực tiếp" else "Con trỏ"

/** Cài đặt chuột/con trỏ: dùng trong màn Bảo mật & cài đặt và trong hộp thoại ở màn stream. */
@Composable
fun PointerSettingsCard(store: PointerSettingsStore, modifier: Modifier = Modifier) {
    val s = store.settings
    Card(modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Chuột và con trỏ", style = MaterialTheme.typography.titleSmall)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                PointerMode.entries.forEach { mode ->
                    FilterChip(
                        selected = s.mode == mode, onClick = { store.update { it.copy(mode = mode) } },
                        label = { Text(mode.title()) }, modifier = Modifier.heightIn(min = 48.dp),
                    )
                }
            }
            Text(
                if (s.mode == PointerMode.DIRECT) "Chạm đâu click đó. Kéo một ngón để kéo thả, hai ngón để cuộn, nhấn giữ để chuột phải."
                else "Trượt một ngón để di chuyển con trỏ, chạm để click. Hai ngón chạm = chuột phải, hai ngón trượt = cuộn, chạm rồi chạm-giữ-trượt = kéo.",
                style = MaterialTheme.typography.bodySmall,
            )
            Text("Tốc độ con trỏ: ${"%.1f".format(s.safeSpeed)}×", style = MaterialTheme.typography.bodyMedium)
            Slider(
                value = s.safeSpeed, onValueChange = { v -> store.update { it.copy(speed = v) } }, valueRange = PointerSettings.SPEED_RANGE,
                enabled = s.mode == PointerMode.TRACKPAD, modifier = Modifier.semantics { contentDescription = "Tốc độ con trỏ" },
            )
            SwitchRow("Cuộn tự nhiên", s.naturalScroll) { v -> store.update { it.copy(naturalScroll = v) } }
            SwitchRow("Nhấn giữ để chuột phải", s.longPressRightClick) { v -> store.update { it.copy(longPressRightClick = v) } }
        }
    }
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange, modifier = Modifier.semantics { contentDescription = label })
    }
}
