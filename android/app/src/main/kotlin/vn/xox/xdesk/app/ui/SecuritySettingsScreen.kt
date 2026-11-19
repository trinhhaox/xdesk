package vn.xox.xdesk.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import vn.xox.xdesk.app.PointerSettingsStore
import vn.xox.xdesk.app.Screen
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.update.UpdateController

/**
 * Màn "Cài đặt": Hiển thị (Bản sao / Mở rộng và kiểu vừa khung), Chuột và con trỏ, rồi Bảo mật (dấu vân tay, máy Mac đã ghép, đặt lại danh tính)
 * và Cập nhật. "Máy Mac đã ghép" là một trang con (mũi tên chỉ sang phải).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SecuritySettingsScreen(controller: ViewerController, updates: UpdateController) {
    val pointerStore = LocalContext.current.let { context -> remember { PointerSettingsStore(context) } }
    var pairedPage by rememberSaveable { mutableStateOf(false) }
    var confirmReset by remember { mutableStateOf(false) }
    BackHandler(enabled = pairedPage) { pairedPage = false }
    Scaffold(
        topBar = {
            if (pairedPage) SettingsTopBar("Máy Mac đã ghép") { pairedPage = false }
            else SettingsTopBar("Cài đặt") { controller.screen = Screen.HOSTS }
        },
        contentWindowInsets = WindowInsets(0), containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        if (pairedPage) {
            PairedHostsPage(controller, Modifier.padding(padding))
        } else {
            LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                item { SectionTitle("Hiển thị") }
                item { DisplaySettingsCard(controller.display, pointerStore) }
                item { SectionTitle("Chuột và con trỏ") }
                item { PointerSettingsCard(pointerStore) }
                item { SectionTitle("Bảo mật") }
                item {
                    SettingsGroup {
                        SettingsRow("Dấu vân tay thiết bị này", controller.fingerprint ?: (controller.identityError ?: "Không có"), supportingMono = true)
                        SettingsDivider()
                        SettingsRow("Máy Mac đã ghép", "${controller.knownHosts.size} máy", chevron = true) { pairedPage = true }
                        SettingsDivider()
                        SettingsRow("Đặt lại danh tính", "Tạo khoá mới; các máy Mac đã ghép sẽ không nhận ra điện thoại này", danger = true) { confirmReset = true }
                    }
                }
                item { Text("Khoá riêng được bọc bằng Android Keystore và không nằm trong bản sao lưu.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                item { UpdateCard(updates) }
            }
        }
    }
    if (confirmReset) {
        ConfirmDialog("Đặt lại danh tính?", "Tạo khoá mới; mọi máy Mac đã ghép sẽ không nhận ra điện thoại này nữa.", "Đặt lại",
            { controller.resetIdentity(); confirmReset = false }) { confirmReset = false }
    }
}

@Composable
private fun SectionTitle(text: String) = Text(text, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onBackground)
