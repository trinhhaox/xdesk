package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.Screen
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.pairWithQr
import vn.xox.xdesk.transport.ViewerTarget

/** Ghép đôi: quét QR (xin quyền camera chỉ ở đây) hoặc so mã 6 số với host đã chọn/nhập tay. */
@Composable
fun PairingScreen(controller: ViewerController) {
    var tab by remember { mutableIntStateOf(0) }
    Column(Modifier.fillMaxSize()) {
        TabRow(selectedTabIndex = tab) {
            Tab(tab == 0, { tab = 0 }, text = { Text("Quét QR") })
            Tab(tab == 1, { tab = 1 }, text = { Text("So mã 6 số") })
        }
        Column(Modifier.weight(1f).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (tab == 0) {
                Text("Trên Mac, mở Xdesk → Ghép đôi thiết bị mới rồi đưa mã QR vào khung.")
                QrScanner(Modifier.fillMaxWidth().weight(1f), onResult = controller::pairWithQr)
            } else {
                SasPairing(controller)
            }
        }
        OutlinedButton({ controller.screen = Screen.HOSTS }, Modifier.fillMaxWidth().padding(16.dp)) { Text("Quay lại") }
    }
}

@Composable
private fun SasPairing(controller: ViewerController) {
    var address by remember { mutableStateOf(controller.pairTarget?.address.orEmpty()) }
    val target = ViewerTarget.parse(address)
    Text("Nhập địa chỉ Mac, bấm Ghép đôi, rồi so mã 6 số hiện ở hai máy. Chỉ bấm Khớp trên Mac khi hai mã giống nhau.")
    OutlinedTextField(address, { address = it }, Modifier.fillMaxWidth(), label = { Text("host:port") }, singleLine = true)
    Row { Button(onClick = { target?.let(controller::pairWithSas) }, enabled = target != null) { Text("Ghép đôi") } }
}

/** Mã SAS "NNN NNN" cỡ lớn trong lúc chờ người dùng bấm "Khớp" trên Mac. */
@Composable
fun SasCodeView(code: String, modifier: Modifier = Modifier) {
    Column(modifier.padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("So mã với màn hình Mac", style = MaterialTheme.typography.titleMedium)
        Text(code, fontSize = 56.sp, fontFamily = FontFamily.Monospace, textAlign = TextAlign.Center)
        Text("Nếu hai mã giống nhau, bấm Khớp trên Mac. Nếu khác, bấm Không khớp: có thể đang bị nghe lén.", textAlign = TextAlign.Center)
    }
}
