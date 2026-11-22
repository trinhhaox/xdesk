package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import vn.xox.xdesk.app.KeyboardStyle
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.input.KeyboardGeometryCalculator

/**
 * Chế độ "Bàn phím". Kiểu bàn phím (Mac | văn bản) chọn ở thanh trên.
 * Bàn phím Mac ngang: lấp đầy vùng. Dọc: vùng chuột (dùng lại cử chỉ trackpad) trên, bàn phím Mac đầy đủ dưới.
 */
@Composable
internal fun KeyboardTabContent(
    style: KeyboardStyle,
    controller: ViewerController,
    landscape: Boolean,
    trackpad: TrackpadActions,
    activeMods: Int,
    inputText: String,
    onInputTextChange: (String) -> Unit,
    onSendText: () -> Unit,
    onToggleMod: (Int) -> Unit,
    onKey: (Int, Int) -> Unit,
) {
    when {
        style == KeyboardStyle.TEXT -> TextKeyboardContent(landscape, activeMods, inputText, onInputTextChange, onSendText, onToggleMod, onKey)
        landscape -> MacKeyboardPanel(controller, landscape = true, Modifier.fillMaxSize())
        else -> BoxWithConstraints(Modifier.fillMaxSize()) {
            val split = KeyboardGeometryCalculator.portraitSplit(maxHeight.value)
            Column(Modifier.fillMaxSize()) {
                TrackpadSurface(trackpad, Modifier.fillMaxWidth().height(split.trackpadHeight.dp).padding(horizontal = 8.dp, vertical = 4.dp))
                MacKeyboardPanel(controller, landscape = false, Modifier.fillMaxWidth().height(split.keyboardHeight.dp))
            }
        }
    }
}
