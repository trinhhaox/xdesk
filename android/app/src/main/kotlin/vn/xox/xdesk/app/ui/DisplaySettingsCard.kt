package vn.xox.xdesk.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.DisplaySettingsStore
import vn.xox.xdesk.app.PointerSettingsStore
import vn.xox.xdesk.app.WorkMode
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

internal fun MirrorFit.icon(): ImageVector = when (this) {
    MirrorFit.NATIVE -> XdeskIcons.Laptop
    MirrorFit.FIT_DEVICE -> XdeskIcons.Phone
    MirrorFit.TOUCH -> XdeskIcons.HandTap
}

fun ScreenMode.title() = if (this == ScreenMode.MIRROR) "Chiếu màn hình Mac" else "Màn hình phụ"

/** Một dòng tóm tắt cài đặt hiển thị, ví dụ "Chiếu màn hình Mac · Vừa với điện thoại · Chạm trực tiếp". */
fun settingsSummary(mode: ScreenMode, fit: MirrorFit, pointer: PointerMode): String =
    listOfNotNull(mode.title(), fit.title().takeIf { mode == ScreenMode.MIRROR }, pointer.title()).joinToString(" · ")

/** "Chế độ làm việc mặc định": gom đủ 5 chế độ (Chiếu màn hình Mac, Màn hình phụ, Chuột cảm ứng, Bàn phím ảo, Trình chiếu & Phím số). */
@Composable
internal fun WorkModeSettingsGroup(display: DisplaySettingsStore) = Group(
    header = "Chế độ làm việc mặc định",
    footer = "Chế độ sẽ tự mở khi bạn chạm vào máy Mac. Bạn vẫn có thể đổi nhanh giữa 5 chế độ ngay khi đang kết nối.",
) {
    WorkMode.entries.forEachIndexed { index, workMode ->
        if (index > 0) GroupDivider(ChoiceDividerIndent)
        ChoiceRow(workMode.icon(), workMode.title, workMode.summary, display.defaultWorkMode == workMode) {
            display.selectDefaultWorkMode(workMode)
        }
    }
}

/** "Kiểu chiếu màn hình": ba lựa chọn có biểu tượng và mô tả; chọn "Tối ưu thao tác" thì gợi ý dùng chuột Chạm trực tiếp. */
@Composable
internal fun MirrorFitGroup(display: DisplaySettingsStore, pointer: PointerSettingsStore) = Group("Kiểu chiếu màn hình") {
    DisplaySettingsStore.SUPPORTED_FITS.forEachIndexed { index, fit ->
        if (index > 0) GroupDivider(ChoiceDividerIndent)
        ChoiceRow(fit.icon(), fit.title(), fit.summary(), display.fit == fit) { display.selectFit(fit) }
    }
    if (display.fit == MirrorFit.TOUCH && pointer.settings.mode != PointerMode.DIRECT) {
        GroupDivider()
        Text(
            "Gợi ý: dùng chế độ chuột Chạm trực tiếp",
            Modifier.clickable { pointer.update { it.copy(mode = PointerMode.DIRECT) } }.padding(XdeskDims.rowPad),
            fontSize = 14.sp,
            color = MaterialTheme.colorScheme.primary,
        )
    }
}
