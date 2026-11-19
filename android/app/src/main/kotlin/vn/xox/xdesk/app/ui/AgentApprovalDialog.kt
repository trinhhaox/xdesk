package vn.xox.xdesk.app.ui

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import vn.xox.xdesk.transport.AgentApprovalRequest

internal fun agentApprovalTitle(agentName: String): String = "$agentName muốn điều khiển máy Mac"

/**
 * Hộp thoại duyệt quyền điều khiển cho agent AI. Không đóng khi chạm ra ngoài (phải chọn rõ);
 * controller tự đặt `request` về null khi hết hạn hoặc khi Mac đã trả lời trước.
 */
@Composable
fun AgentApprovalDialog(request: AgentApprovalRequest, onAnswer: (allow: Boolean) -> Unit) {
    AlertDialog(
        onDismissRequest = {},
        title = { Text(agentApprovalTitle(request.agentName)) },
        text = { if (request.summary.isNotEmpty()) Text(request.summary) },
        confirmButton = { TextButton(onClick = { onAnswer(true) }) { Text("Cho phép") } },
        dismissButton = { TextButton(onClick = { onAnswer(false) }) { Text("Từ chối") } },
    )
}
