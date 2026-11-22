package vn.xox.xdesk.app.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.ui.theme.XdeskOverlay

/**
 * Phủ lên video khi host báo Mac khoá/tắt màn hình (`host.state videoAvailable:false`): phiên vẫn sống nhưng chưa có hình.
 * Nút "Mở khoá Mac" nằm ngay đây cùng nút Ngắt kết nối (chặn chạm để không gửi click xuống Mac khi chưa có hình).
 */
@Composable
internal fun HostLockedOverlay(controller: ViewerController) {
    val locked = controller.hostState?.locked == true
    Box(Modifier.fillMaxSize().background(Color.Black).pointerInput(Unit) { detectTapGestures { } }, contentAlignment = Alignment.Center) {
        OverlayCard {
            Text(
                if (locked) "Mac đang khoá" else "Màn hình Mac đang tắt",
                color = XdeskOverlay.content, fontSize = 17.sp, fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
            )
            Text(
                "Bấm Mở khoá Mac để đánh thức và mở khoá. Hình sẽ hiện lại khi Mac mở khoá.",
                color = XdeskOverlay.content.copy(alpha = 0.8f), fontSize = 14.sp, textAlign = TextAlign.Center,
            )
            Button(
                controller::sendSystemUnlock, Modifier.fillMaxWidth().heightIn(min = 48.dp),
                colors = ButtonDefaults.buttonColors(containerColor = XdeskOverlay.accentLight),
            ) { Text("Mở khoá Mac") }
            OutlinedButton(
                controller::disconnect, Modifier.fillMaxWidth().heightIn(min = 48.dp), border = BorderStroke(1.dp, XdeskOverlay.outline),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = XdeskOverlay.content),
            ) { Text("Ngắt kết nối") }
        }
    }
}
