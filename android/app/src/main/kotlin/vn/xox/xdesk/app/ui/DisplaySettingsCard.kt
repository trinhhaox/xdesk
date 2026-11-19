package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.clickable
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.DisplaySettingsStore
import vn.xox.xdesk.app.PointerSettingsStore
import vn.xox.xdesk.app.input.PointerMode
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

private fun MirrorFit.icon(): ImageVector = when (this) {
    MirrorFit.NATIVE -> XdeskIcons.Laptop
    MirrorFit.FIT_DEVICE -> XdeskIcons.Phone
    MirrorFit.TOUCH -> XdeskIcons.HandTap
}

fun ScreenMode.title() = if (this == ScreenMode.MIRROR) "Bản sao" else "Mở rộng"

/** Một dòng tóm tắt cài đặt hiển thị cho màn chính, ví dụ "Bản sao · Vừa với điện thoại · Chạm trực tiếp". */
fun settingsSummary(mode: ScreenMode, fit: MirrorFit, pointer: PointerMode): String =
    listOfNotNull(mode.title(), fit.title().takeIf { mode == ScreenMode.MIRROR }, pointer.title()).joinToString(" · ")

/** "Chế độ hiển thị": nút phân đoạn Bản sao | Mở rộng và chú thích giải thích chế độ đang chọn. */
@Composable
internal fun DisplayModeGroup(display: DisplaySettingsStore) {
    val footer = if (display.mode == ScreenMode.EXTEND) "Điện thoại là màn hình thứ hai bên phải Mac. Kéo cửa sổ sang để dùng."
    else "Điện thoại hiện đúng màn hình Mac. Chọn bên dưới Mac giữ nguyên hay đổi theo điện thoại."
    Group("Chế độ hiển thị", footer) {
        Box(Modifier.padding(12.dp)) {
            SegmentedPicker(listOf(ScreenMode.MIRROR, ScreenMode.EXTEND).map { it to it.title() }, display.mode) { display.selectMode(it) }
        }
    }
}

/** "Kiểu bản sao": ba lựa chọn có biểu tượng và mô tả; chọn "Tối ưu thao tác" thì gợi ý (không ép) dùng chuột Chạm trực tiếp. */
@Composable
internal fun MirrorFitGroup(display: DisplaySettingsStore, pointer: PointerSettingsStore) = Group("Kiểu bản sao") {
    DisplaySettingsStore.SUPPORTED_FITS.forEachIndexed { index, fit ->
        if (index > 0) GroupDivider(ChoiceDividerIndent)
        ChoiceRow(fit.icon(), fit.title(), fit.summary(), display.fit == fit) { display.selectFit(fit) }
    }
    if (display.fit == MirrorFit.TOUCH && pointer.settings.mode != PointerMode.DIRECT) {
        GroupDivider()
        Text(
            "Gợi ý: dùng chế độ chuột Chạm trực tiếp", Modifier.clickable { pointer.update { it.copy(mode = PointerMode.DIRECT) } }.padding(XdeskDims.rowPad),
            fontSize = 14.sp, color = MaterialTheme.colorScheme.primary,
        )
    }
}
