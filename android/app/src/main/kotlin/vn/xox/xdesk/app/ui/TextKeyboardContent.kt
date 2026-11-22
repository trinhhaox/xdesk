package vn.xox.xdesk.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.input.HidKeys
import vn.xox.xdesk.app.ui.theme.XdeskOverlay
import vn.xox.xdesk.transport.InputModifiers

private val Gap = 8.dp

private class TextKey(val label: String, val usage: Int, val mods: Int = 0, val weight: Float = 1f)

private val EditKeys = listOf(
    TextKey("Esc", HidKeys.ESCAPE), TextKey("Tab", HidKeys.TAB), TextKey("Space", HidKeys.SPACE, weight = 1.4f),
    TextKey("⌫ Del", HidKeys.BACKSPACE), TextKey("↩ Enter", HidKeys.ENTER, weight = 1.2f),
)
private val ShortcutKeys = listOf(
    TextKey("⌘ C", 0x06, InputModifiers.COMMAND), TextKey("⌘ V", 0x19, InputModifiers.COMMAND), TextKey("⌘ A", 0x04, InputModifiers.COMMAND),
)
private val ArrowKeys = listOf(
    TextKey("←", HidKeys.LEFT), TextKey("↑", HidKeys.UP), TextKey("↓", HidKeys.DOWN), TextKey("→", HidKeys.RIGHT),
)

/** Chế độ "Gõ văn bản": ô nhập tiếng Việt + phím bổ trợ dính + phím tắt. Ngang: ô nhập một hàng + 2 hàng phím tràn rộng, không cuộn. */
@Composable
internal fun TextKeyboardContent(
    landscape: Boolean,
    activeMods: Int,
    inputText: String,
    onInputTextChange: (String) -> Unit,
    onSendText: () -> Unit,
    onToggleMod: (Int) -> Unit,
    onKey: (Int, Int) -> Unit,
) {
    if (landscape) {
        Column(Modifier.fillMaxSize().padding(horizontal = 10.dp, vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            InputRow(inputText, onInputTextChange, onSendText)
            Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Gap)) {
                ModifierKeys(activeMods, onToggleMod, Modifier.weight(4f))
                EditKeys.forEach { TextKeyButton(it, Modifier.weight(it.weight), onKey) }
            }
            Row(Modifier.weight(1f).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Gap)) {
                (ShortcutKeys + ArrowKeys).forEach { TextKeyButton(it, Modifier.weight(it.weight), onKey) }
            }
        }
    } else {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            InputRow(inputText, onInputTextChange, onSendText)
            ModifierRow(activeMods, onToggleMod, Modifier.height(44.dp))
            Row(Modifier.fillMaxWidth().height(44.dp), horizontalArrangement = Arrangement.spacedBy(Gap)) {
                EditKeys.forEach { TextKeyButton(it, Modifier.weight(it.weight), onKey) }
            }
            Row(Modifier.fillMaxWidth().height(44.dp), horizontalArrangement = Arrangement.spacedBy(Gap)) {
                ShortcutKeys.forEach { TextKeyButton(it, Modifier.weight(it.weight), onKey) }
            }
            Row(Modifier.fillMaxWidth().height(46.dp), horizontalArrangement = Arrangement.spacedBy(Gap)) {
                ArrowKeys.forEach { TextKeyButton(it, Modifier.weight(it.weight), onKey) }
            }
        }
    }
}

@Composable
private fun TextKeyButton(key: TextKey, modifier: Modifier, onKey: (Int, Int) -> Unit) {
    KeyCapButton(key.label, modifier.fillMaxSize(), fontSize = 14) { onKey(key.usage, key.mods) }
}

@Composable
private fun ModifierRow(activeMods: Int, onToggleMod: (Int) -> Unit, modifier: Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Gap)) { ModifierKeys(activeMods, onToggleMod, Modifier.weight(1f)) }
}

@Composable
private fun ModifierKeys(activeMods: Int, onToggleMod: (Int) -> Unit, modifier: Modifier) {
    Row(modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(Gap)) {
        listOf("⌘ Cmd" to InputModifiers.COMMAND, "⌥ Opt" to InputModifiers.OPTION, "⌃ Ctrl" to InputModifiers.CONTROL, "⇧ Shift" to InputModifiers.SHIFT)
            .forEach { (label, bit) ->
                KeyCapButton(label, Modifier.weight(1f).fillMaxSize(), active = (activeMods and bit) != 0, fontSize = 12) { onToggleMod(bit) }
            }
    }
}

@Composable
private fun InputRow(inputText: String, onInputTextChange: (String) -> Unit, onSendText: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Gap)) {
        OutlinedTextField(
            value = inputText,
            onValueChange = onInputTextChange,
            modifier = Modifier.weight(1f),
            placeholder = { Text("Nhập tiếng Việt / văn bản sang Mac…", fontSize = 13.sp, color = XdeskOverlay.contentMuted, maxLines = 1, overflow = TextOverflow.Ellipsis) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(onSend = { onSendText() }),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = XdeskOverlay.accentLight,
                unfocusedBorderColor = XdeskOverlay.divider,
                focusedTextColor = XdeskOverlay.content,
                unfocusedTextColor = XdeskOverlay.content,
                cursorColor = XdeskOverlay.accentLight,
            ),
        )
        Button(
            onClick = onSendText,
            enabled = inputText.isNotEmpty(),
            modifier = Modifier.height(56.dp),
            shape = RoundedCornerShape(10.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = XdeskOverlay.accent,
                contentColor = XdeskOverlay.content,
                disabledContainerColor = XdeskOverlay.key,
                disabledContentColor = XdeskOverlay.contentDisabled,
            ),
        ) {
            Text("Gửi", fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = 1, softWrap = false)
        }
    }
}
