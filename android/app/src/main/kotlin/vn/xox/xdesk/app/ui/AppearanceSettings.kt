package vn.xox.xdesk.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.vector.ImageVector
import vn.xox.xdesk.app.AppearanceSetting
import vn.xox.xdesk.app.AppearanceStore

private fun AppearanceSetting.title() = when (this) {
    AppearanceSetting.DARK -> "Tối"
    AppearanceSetting.LIGHT -> "Sáng"
    AppearanceSetting.SYSTEM -> "Theo hệ thống"
}

private fun AppearanceSetting.summary() = when (this) {
    AppearanceSetting.DARK -> "Nền tối, dịu mắt. Mặc định."
    AppearanceSetting.LIGHT -> "Nền sáng."
    AppearanceSetting.SYSTEM -> "Đổi theo cài đặt Sáng/Tối của điện thoại."
}

private fun AppearanceSetting.icon(): ImageVector = when (this) {
    AppearanceSetting.DARK -> XdeskIcons.Moon
    AppearanceSetting.LIGHT -> XdeskIcons.Sun
    AppearanceSetting.SYSTEM -> XdeskIcons.HalfCircle
}

/** "Giao diện": Tối (mặc định) | Sáng | Theo hệ thống; áp dụng ngay, cùng vị trí và chữ với bản iOS. */
@Composable
internal fun AppearanceGroup(store: AppearanceStore) = Group("Giao diện") {
    AppearanceSetting.entries.forEachIndexed { index, option ->
        if (index > 0) GroupDivider(ChoiceDividerIndent)
        ChoiceRow(option.icon(), option.title(), option.summary(), store.setting == option) { store.select(option) }
    }
}

/** Kho giao diện hiện hành cho các màn cài đặt (đặt ở gốc trong MainActivity). */
val LocalAppearance = staticCompositionLocalOf<AppearanceStore> { error("AppearanceStore chưa được cung cấp") }
