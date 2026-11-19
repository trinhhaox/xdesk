package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.ui.unit.sp
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import vn.xox.xdesk.app.update.UpdateController
import vn.xox.xdesk.app.update.UpdateState
import vn.xox.xdesk.update.UpdateManifest

/** Hộp thoại cập nhật dùng chung cho màn danh sách host và màn Bảo mật. */
@Composable
fun UpdatePrompt(updates: UpdateController) {
    when (val s = updates.state) {
        is UpdateState.Available -> OfferDialog(s.manifest, "Cập nhật", { updates.install(s.manifest) }, updates::dismiss)
        is UpdateState.Deferred -> OfferDialog(s.manifest, "Cập nhật", { updates.install(s.manifest) }, updates::dismiss,
            warning = "Đang kết nối tới máy Mac nên chưa cài được. Ngắt kết nối rồi bấm Cập nhật.")
        is UpdateState.Downloading -> ProgressDialog("Đang tải ${s.manifest.versionName}…", s.percent / 100f)
        is UpdateState.Installing -> ProgressDialog("Đang chuyển cho trình cài đặt của Android…", null)
        is UpdateState.NeedsPermission -> AlertDialog(
            onDismissRequest = updates::dismiss, title = { Text("Cho phép cài đặt từ Xdesk") },
            text = { Text("Android cần bạn bật \"Cho phép từ nguồn này\" cho Xdesk để cài bản cập nhật. Sau khi bật, quay lại Xdesk và bấm Cập nhật lần nữa.") },
            confirmButton = { TextButton(onClick = updates::openUnknownSourcesSettings) { Text("Mở cài đặt") } },
            dismissButton = { TextButton(onClick = updates::dismiss) { Text("Để sau") } },
        )
        is UpdateState.Failed -> AlertDialog(
            onDismissRequest = updates::dismiss, title = { Text("Không cập nhật được") }, text = { Text(s.message) },
            confirmButton = { TextButton(onClick = updates::dismiss) { Text("Đóng") } },
        )
        UpdateState.Idle, UpdateState.Checking, UpdateState.UpToDate -> Unit
    }
}

/** Nhóm "Cập nhật" cuối màn Cài đặt (chỉ có ở Android): phiên bản hiện tại, trạng thái và nút kiểm tra thủ công. */
@Composable
fun UpdateCard(updates: UpdateController) = Group("Cập nhật", footer = statusText(updates.state)) {
    GroupRow { Text("Phiên bản hiện tại", Modifier.weight(1f), fontSize = 17.sp); Text("${updates.installedVersionName} (${updates.installedVersionCode})", fontSize = 17.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    GroupDivider()
    GroupRow(if (updates.state != UpdateState.Checking) updates::checkNow else null) {
        Text("Kiểm tra cập nhật", fontSize = 17.sp, color = MaterialTheme.colorScheme.primary)
    }
}

private fun statusText(state: UpdateState): String = when (state) {
    UpdateState.Checking -> "Đang kiểm tra…"
    UpdateState.UpToDate -> "Bạn đang dùng bản mới nhất."
    is UpdateState.Available -> "Có bản mới ${state.manifest.versionName}."
    is UpdateState.Deferred -> "Có bản mới ${state.manifest.versionName}, sẽ cài khi không còn kết nối."
    else -> "Xdesk tự kiểm tra mỗi 24 giờ khi mở app."
}

@Composable
private fun OfferDialog(manifest: UpdateManifest, confirm: String, onConfirm: () -> Unit, onDismiss: () -> Unit, warning: String? = null) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Có bản mới ${manifest.versionName}") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Dung lượng ${"%.1f".format(manifest.size / 1_048_576.0)} MB")
                if (manifest.releaseNotes.isNotBlank()) Text(manifest.releaseNotes)
                warning?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = { TextButton(onClick = onConfirm) { Text(confirm) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Để sau") } },
    )
}

@Composable
private fun ProgressDialog(title: String, progress: Float?) {
    AlertDialog(
        onDismissRequest = {}, title = { Text(title) },
        text = { if (progress == null) LinearProgressIndicator(Modifier.fillMaxWidth()) else LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth()) },
        confirmButton = {},
    )
}
