package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import vn.xox.xdesk.app.DisplaySettingsStore
import vn.xox.xdesk.app.PointerSettingsStore
import vn.xox.xdesk.app.input.PointerMode
import vn.xox.xdesk.app.ui.theme.XdeskCard
import vn.xox.xdesk.wire.MirrorFit
import vn.xox.xdesk.wire.ScreenMode

fun MirrorFit.title() = when (this) {
    MirrorFit.NATIVE -> "Giống màn hình Mac"
    MirrorFit.FIT_DEVICE -> "Vừa với điện thoại"
    MirrorFit.TOUCH -> "Tối ưu thao tác"
}

private fun MirrorFit.summary() = when (this) {
    MirrorFit.NATIVE -> "Giữ nguyên Mac, xem cả màn hình rồi phóng to bằng hai ngón."
    MirrorFit.FIT_DEVICE -> "Mac đổi theo kích thước và chiều xoay của điện thoại."
    MirrorFit.TOUCH -> "Như Vừa với điện thoại nhưng nút và chữ to hơn, dễ chạm."
}

fun ScreenMode.title() = if (this == ScreenMode.MIRROR) "Bản sao" else "Mở rộng"

/** Một dòng tóm tắt cài đặt hiển thị cho màn chính, ví dụ "Bản sao · Vừa với điện thoại · Chạm trực tiếp". */
fun settingsSummary(mode: ScreenMode, fit: MirrorFit, pointer: PointerMode): String =
    listOfNotNull(mode.title(), fit.title().takeIf { mode == ScreenMode.MIRROR }, pointer.title()).joinToString(" · ")

/** Chế độ hiển thị: Bản sao / Mở rộng là một lựa chọn duy nhất (nút phân đoạn, vai trò radio); với Bản sao là kiểu vừa khung (nhóm radio). */
@Composable
fun DisplaySettingsCard(display: DisplaySettingsStore, pointer: PointerSettingsStore, modifier: Modifier = Modifier) {
    XdeskCard(modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            val modes = listOf(ScreenMode.MIRROR, ScreenMode.EXTEND)
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                modes.forEachIndexed { index, mode ->
                    SegmentedButton(
                        selected = display.mode == mode, onClick = { display.selectMode(mode) },
                        shape = SegmentedButtonDefaults.itemShape(index, modes.size), modifier = Modifier.heightIn(min = 48.dp),
                    ) { Text(mode.title()) }
                }
            }
            if (display.mode == ScreenMode.EXTEND) {
                Text("Điện thoại là màn hình thứ hai bên phải Mac. Kéo cửa sổ sang để dùng.", style = MaterialTheme.typography.bodyMedium)
            } else {
                FitOptions(display)
                if (display.fit == MirrorFit.TOUCH && pointer.settings.mode != PointerMode.DIRECT) {
                    TextButton({ pointer.update { it.copy(mode = PointerMode.DIRECT) } }) { Text("Gợi ý: dùng chế độ chuột Chạm trực tiếp") }
                }
            }
        }
    }
}

@Composable
private fun FitOptions(display: DisplaySettingsStore) {
    Column(Modifier.selectableGroup()) {
        DisplaySettingsStore.SUPPORTED_FITS.forEach { fit ->
            Row(
                Modifier.fillMaxWidth().heightIn(min = 56.dp).selectable(display.fit == fit, onClick = { display.selectFit(fit) }, role = Role.RadioButton),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(display.fit == fit, onClick = null)
                Column(Modifier.padding(start = 12.dp, top = 8.dp, bottom = 8.dp)) {
                    Text(fit.title(), style = MaterialTheme.typography.bodyLarge)
                    Text(fit.summary(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}
