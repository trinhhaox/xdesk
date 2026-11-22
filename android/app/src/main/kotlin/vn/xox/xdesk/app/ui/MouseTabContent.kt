package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import vn.xox.xdesk.transport.InputButton

/** Chế độ "Chuột": vùng cảm ứng lấp đầy + hai nút chuột (dọc: dưới đáy 50/50; ngang: cột bên phải). */
@Composable
internal fun MouseTabContent(
    landscape: Boolean,
    isLeftDown: Boolean,
    isRightDown: Boolean,
    actions: TrackpadActions,
) {
    val left = @Composable { m: Modifier -> KeyCapButton("Chuột Trái", m, active = isLeftDown, fontSize = 15) { actions.onClick(InputButton.LEFT) } }
    val right = @Composable { m: Modifier -> KeyCapButton("Chuột Phải", m, active = isRightDown, fontSize = 15) { actions.onClick(InputButton.RIGHT) } }
    if (landscape) {
        Row(Modifier.fillMaxSize().padding(horizontal = 10.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            TrackpadSurface(actions, Modifier.weight(1f).fillMaxHeight())
            Column(Modifier.width(140.dp).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                left(Modifier.weight(1f).fillMaxWidth())
                right(Modifier.weight(1f).fillMaxWidth())
            }
        }
    } else {
        Column(Modifier.fillMaxSize().padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            TrackpadSurface(actions, Modifier.weight(1f).fillMaxWidth())
            Row(Modifier.fillMaxWidth().height(56.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                left(Modifier.weight(1f).fillMaxHeight())
                right(Modifier.weight(1f).fillMaxHeight())
            }
        }
    }
}
