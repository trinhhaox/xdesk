package vn.xox.xdesk.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import vn.xox.xdesk.app.PointerSettingsStore
import vn.xox.xdesk.app.Screen
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.forgetHost
import vn.xox.xdesk.app.update.UpdateController
import vn.xox.xdesk.transport.KnownHost
import vn.xox.xdesk.wire.ScreenMode

private enum class SettingsPage { ROOT, POINTER, SECURITY }

/**
 * Màn "Cài đặt" theo iOS: Chế độ hiển thị, Kiểu bản sao, Giao diện, Điều khiển › Chuột và con trỏ, Bảo mật › Thiết bị và máy đã ghép
 * (và Cập nhật, chỉ có ở Android). Trang con thay nội dung tại chỗ; nút Quay lại hệ thống đi lùi một cấp.
 */
@Composable
fun SecuritySettingsScreen(controller: ViewerController, updates: UpdateController) {
    val pointerStore = LocalContext.current.let { context -> remember { PointerSettingsStore(context) } }
    var page by rememberSaveable { mutableStateOf(SettingsPage.ROOT) }
    var confirmReset by remember { mutableStateOf(false) }
    var forgetting by remember { mutableStateOf<KnownHost?>(null) }
    BackHandler(enabled = page != SettingsPage.ROOT) { page = SettingsPage.ROOT }
    when (page) {
        SettingsPage.ROOT -> SettingsScaffold("Cài đặt", { controller.screen = Screen.HOSTS }) {
            item { DisplayModeGroup(controller.display) }
            if (controller.display.mode == ScreenMode.MIRROR) item { MirrorFitGroup(controller.display, pointerStore) }
            item { AppearanceGroup(LocalAppearance.current) }
            item { Group("Điều khiển") { ValueRow("Chuột và con trỏ", pointerStore.settings.mode.title()) { page = SettingsPage.POINTER } } }
            item { Group("Bảo mật") { ValueRow("Thiết bị và máy đã ghép", "${controller.knownHosts.size} máy") { page = SettingsPage.SECURITY } } }
            item { UpdateCard(updates) }
        }
        SettingsPage.POINTER -> SettingsScaffold("Chuột và con trỏ", { page = SettingsPage.ROOT }) { item { PointerSettingsGroups(pointerStore) } }
        SettingsPage.SECURITY -> SettingsScaffold("Bảo mật", { page = SettingsPage.ROOT }) {
            securityPageItems(controller, { forgetting = it }, { confirmReset = true })
        }
    }
    if (confirmReset) {
        ConfirmDialog("Đặt lại danh tính?", "Tạo khoá mới; mọi máy Mac đã ghép sẽ không nhận ra điện thoại này nữa.", "Đặt lại",
            { controller.resetIdentity(); confirmReset = false }) { confirmReset = false }
    }
    forgetting?.let { host -> ForgetHostDialog(host, { controller.forgetHost(host.id); forgetting = null }) { forgetting = null } }
}
