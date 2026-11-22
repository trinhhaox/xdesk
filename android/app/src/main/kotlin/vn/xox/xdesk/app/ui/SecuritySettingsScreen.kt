package vn.xox.xdesk.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import vn.xox.xdesk.app.PointerSettingsStore
import vn.xox.xdesk.app.Screen
import vn.xox.xdesk.app.TailscaleState
import vn.xox.xdesk.app.TailscaleSupport
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.WorkMode
import vn.xox.xdesk.app.forgetHost
import vn.xox.xdesk.app.ui.theme.extras
import vn.xox.xdesk.app.update.UpdateController
import vn.xox.xdesk.transport.KnownHost

private enum class SettingsPage { ROOT, POINTER, SECURITY }

/**
 * Màn "Cài đặt" theo iOS: Chế độ làm việc mặc định, Kiểu chiếu màn hình, Kết nối từ xa (Tailscale), Giao diện,
 * Điều khiển › Chuột và con trỏ, Bảo mật › Thiết bị và máy đã ghép (và Cập nhật).
 */
@Composable
fun SecuritySettingsScreen(controller: ViewerController, updates: UpdateController) {
    val context = LocalContext.current
    @Suppress("DEPRECATION")
    val lifecycleOwner = LocalLifecycleOwner.current
    val pointerStore = remember(context) { PointerSettingsStore(context) }
    var tailscaleState by remember { mutableStateOf(TailscaleSupport.detect(context)) }
    var page by rememberSaveable { mutableStateOf(SettingsPage.ROOT) }
    var confirmReset by remember { mutableStateOf(false) }
    var forgetting by remember { mutableStateOf<KnownHost?>(null) }
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                tailscaleState = TailscaleSupport.detect(context)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    BackHandler(enabled = page != SettingsPage.ROOT) { page = SettingsPage.ROOT }
    when (page) {
        SettingsPage.ROOT -> SettingsScaffold("Cài đặt", { controller.screen = Screen.HOSTS }) {
            item { WorkModeSettingsGroup(controller.display) }
            if (controller.display.defaultWorkMode == WorkMode.MIRROR) item { MirrorFitGroup(controller.display, pointerStore) }
            item {
                val tailscaleTint = if (tailscaleState == TailscaleState.ACTIVE) MaterialTheme.colorScheme.tertiary else MaterialTheme.extras.warning
                Group("Kết nối từ xa") {
                    GroupRow({ TailscaleSupport.openOrInstall(context, tailscaleState) }) {
                        RowIcon(XdeskIcons.Tailscale, tint = tailscaleTint)
                        TitleAndSubtitle("Tailscale", tailscaleState.settingsSubtitle, Modifier.padding(start = XdeskDims.iconGap))
                        Text(
                            tailscaleState.statusBadge,
                            color = tailscaleTint,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.padding(end = 8.dp),
                        )
                        ChevronIcon()
                    }
                }
            }
            item { QualityPresetGroup(controller.display, controller.deviceMaxRefreshHz) }
            item { VideoCodecGroup(controller.display) }
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
