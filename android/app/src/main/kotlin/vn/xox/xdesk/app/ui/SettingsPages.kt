package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.clickable
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.forgetHost
import vn.xox.xdesk.app.ui.theme.XdeskCard
import vn.xox.xdesk.transport.KnownHost

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SettingsTopBar(title: String, onBack: () -> Unit) {
    TopAppBar(
        title = { Text(title) }, windowInsets = WindowInsets(0),
        navigationIcon = { IconButton(onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Quay lại") } },
    )
}

/** Nhóm dòng cài đặt trong một thẻ. */
@Composable
internal fun SettingsGroup(content: @Composable ColumnScope.() -> Unit) = XdeskCard(Modifier.fillMaxWidth()) { Column(content = content) }

@Composable
internal fun SettingsDivider() = HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

/** Dòng cài đặt kiểu ListItem: tiêu đề, giá trị phụ và mũi tên khi dẫn tới trang khác. Có `onClick` thì cả dòng bấm được (≥ 48 dp). */
@Composable
internal fun SettingsRow(
    title: String, supporting: String, chevron: Boolean = false, danger: Boolean = false, supportingMono: Boolean = false, onClick: (() -> Unit)? = null,
) {
    ListItem(
        headlineContent = { Text(title, color = if (danger) MaterialTheme.colorScheme.error else Color.Unspecified) },
        supportingContent = { Text(supporting, fontFamily = if (supportingMono) FontFamily.Monospace else null) },
        trailingContent = if (chevron) ({ Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null) }) else null,
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier,
    )
}

/** Trang con: máy Mac đã ghép, mỗi dòng có nút "Quên". */
@Composable
internal fun PairedHostsPage(controller: ViewerController, modifier: Modifier = Modifier) {
    var forgetting by remember { mutableStateOf<KnownHost?>(null) }
    LazyColumn(modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (controller.knownHosts.isEmpty()) item { Text("Chưa ghép máy nào.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        items(controller.knownHosts, key = KnownHost::id) { host ->
            XdeskCard(Modifier.fillMaxWidth()) {
                ListItem(
                    headlineContent = { Text(host.name) },
                    supportingContent = { Text(host.id, fontFamily = FontFamily.Monospace) },
                    trailingContent = { TextButton(onClick = { forgetting = host }) { Text("Quên") } },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
            }
        }
    }
    forgetting?.let { host ->
        ForgetHostDialog(host, { controller.forgetHost(host.id); forgetting = null }) { forgetting = null }
    }
}

@Composable
internal fun ConfirmDialog(title: String, text: String, confirm: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss, title = { Text(title) }, text = { Text(text) },
        confirmButton = { TextButton(onClick = onConfirm) { Text(confirm) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Huỷ") } },
    )
}
