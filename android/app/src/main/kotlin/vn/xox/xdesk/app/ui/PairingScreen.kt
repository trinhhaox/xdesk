package vn.xox.xdesk.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.Screen
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.describe
import vn.xox.xdesk.app.pairWithQr
import vn.xox.xdesk.app.ui.theme.XdeskOverlay
import vn.xox.xdesk.app.ui.theme.extras
import vn.xox.xdesk.transport.ViewerTarget

/**
 * Ghép đôi theo iOS (PairWithMacView): khung quét QR (xin quyền camera chỉ ở đây), "Hoặc dán liên kết ghép đôi", và (Android) "Hoặc so mã 6 số"
 * với host đã chọn/nhập tay.
 */
@Composable
fun PairingScreen(controller: ViewerController) {
    var link by remember { mutableStateOf("") }
    var address by remember { mutableStateOf(controller.pairTarget?.address.orEmpty()) }
    val target = ViewerTarget.parse(address)
    SettingsScaffold("Quét mã QR trên Mac", { controller.screen = Screen.HOSTS }) {
        item {
            Group(footer = "Trên Mac: menu Xdesk → \"Ghép đôi thiết bị mới…\", rồi hướng camera vào mã QR.") {
                Box(
                    Modifier.padding(12.dp).fillMaxWidth().height(280.dp).clip(RoundedCornerShape(12.dp))
                        .border(3.dp, MaterialTheme.colorScheme.primary, RoundedCornerShape(12.dp)),
                ) { QrScanner(Modifier.fillMaxSize(), onResult = controller::pairWithQr) }
            }
        }
        item {
            Group("Hoặc dán liên kết ghép đôi") {
                FormField(link, { link = it }, "xdesk://pair?…")
                GroupDivider()
                ActionRow("Ghép đôi", link.isNotBlank()) { controller.pairWithQr(link.trim()) }
            }
        }
        item {
            Group("Hoặc so mã 6 số", "Nhập địa chỉ Mac, bấm Ghép đôi, rồi so mã 6 số hiện ở hai máy. Chỉ bấm Khớp trên Mac khi hai mã giống nhau.") {
                FormField(address, { address = it }, "192.168.1.10:47800")
                GroupDivider()
                ActionRow("Ghép đôi", target != null) { target?.let(controller::pairWithSas) }
            }
        }
        controller.failure?.let { failure -> item { Text(failure.describe().title, color = MaterialTheme.colorScheme.error, fontSize = 15.sp, modifier = Modifier.padding(horizontal = XdeskDims.gutter)) } }
    }
}

@Composable
private fun FormField(value: String, onChange: (String) -> Unit, placeholder: String) = TextField(
    value, onChange, Modifier.fillMaxWidth().heightIn(min = XdeskDims.rowMin), placeholder = { Text(placeholder) }, singleLine = true,
    colors = TextFieldDefaults.colors(focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent, focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent),
)

@Composable
private fun ActionRow(text: String, enabled: Boolean, onClick: () -> Unit) = GroupRow(if (enabled) onClick else null) {
    Text(text, fontSize = 17.sp, color = if (enabled) MaterialTheme.colorScheme.primary else MaterialTheme.extras.tertiaryLabel)
}

/** Thẻ nổi trên nền video/đen: nền overlay 90%, bo 18, đệm 28, rộng tối đa 360 (như SasView và thẻ "Đang kết nối" của iOS). */
@Composable
internal fun OverlayCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.widthIn(max = 360.dp).background(XdeskOverlay.panel.copy(alpha = 0.9f), RoundedCornerShape(18.dp)).padding(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp), content = content,
    )
}

/**
 * Mã ghép đôi cỡ lớn trong lúc chờ người dùng bấm "Khớp, cho phép" trên Mac (cùng chữ và bố cục SasView của iOS). Chữ co giãn theo sp,
 * có nhãn đọc riêng từng chữ số cho TalkBack.
 */
@Composable
fun SasCodeView(code: String, modifier: Modifier = Modifier) {
    OverlayCard(modifier.padding(24.dp)) {
        Text(
            code, color = XdeskOverlay.accentLight, fontSize = 34.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, maxLines = 1,
            modifier = Modifier.semantics { contentDescription = "Mã ghép đôi ${code.filter { it.isDigit() }.toList().joinToString(" ")}" },
        )
        Text("Trên Mac, kiểm tra cùng mã này rồi bấm \"Khớp, cho phép\".", color = XdeskOverlay.content, textAlign = TextAlign.Center, fontSize = 15.sp)
        CircularProgressIndicator(color = XdeskOverlay.content)
        Text("Đang chờ Mac xác nhận…", color = XdeskOverlay.content, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
    }
}
