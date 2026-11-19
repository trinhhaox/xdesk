package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.material3.FilterChip
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import vn.xox.xdesk.app.StreamInputRouter
import vn.xox.xdesk.app.input.HidKeys
import vn.xox.xdesk.transport.InputModifiers

/** Thanh phím đặc biệt: bộ sửa đổi dính (Ctrl/Option/Cmd/Shift) áp cho phím kế tiếp, rồi tự nhả. */
@Composable
fun KeyBar(router: StreamInputRouter, modifier: Modifier = Modifier) {
    var mods by remember { mutableIntStateOf(0) }
    fun tap(usage: Int) { router.tapKey(usage, mods); mods = 0 }
    Row(modifier.horizontalScroll(rememberScrollState()).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        listOf("⌃" to InputModifiers.CONTROL, "⌥" to InputModifiers.OPTION, "⌘" to InputModifiers.COMMAND, "⇧" to InputModifiers.SHIFT).forEach { (label, bit) ->
            FilterChip(selected = mods and bit != 0, onClick = { mods = mods xor bit }, label = { Text(label) })
        }
        listOf(
            "Esc" to HidKeys.ESCAPE, "Tab" to HidKeys.TAB, "⏎" to HidKeys.ENTER, "⌫" to HidKeys.BACKSPACE,
            "←" to HidKeys.LEFT, "↑" to HidKeys.UP, "↓" to HidKeys.DOWN, "→" to HidKeys.RIGHT,
        ).forEach { (label, usage) -> OutlinedButton(onClick = { tap(usage) }) { Text(label) } }
    }
}
