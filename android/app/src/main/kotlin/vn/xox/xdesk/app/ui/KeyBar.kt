package vn.xox.xdesk.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.StreamInputRouter
import vn.xox.xdesk.app.input.HidKeys
import vn.xox.xdesk.app.input.StickyModifiers.State
import vn.xox.xdesk.app.ui.theme.XdeskOverlay
import vn.xox.xdesk.transport.InputModifiers

val KeyBarHeight = 48.dp

/**
 * Thanh phím phụ gắn trên bàn phím ảo: phím riêng của Mac (Esc, Tab, mũi tên; không có ⌫ ↩ vì bàn phím ảo đã có) và ⌃ ⌥ ⌘ ⇧ dính
 * (chạm một lần áp cho phím kế tiếp, chạm hai lần để khoá). Chữ Telex đang soạn hiện nhỏ phía trên thanh.
 */
@Composable
fun KeyBar(router: StreamInputRouter, onHide: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().background(XdeskOverlay.panel)) {
        if (router.composingPreview.isNotEmpty()) {
            Text(
                router.composingPreview, color = XdeskOverlay.content, fontSize = 15.sp,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp).semantics { contentDescription = "Đang soạn: ${router.composingPreview}" },
            )
        }
        Row(Modifier.height(KeyBarHeight).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Row(Modifier.weight(1f).horizontalScroll(rememberScrollState()).padding(horizontal = 4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                ModifierKey("⌘", "Command", router, InputModifiers.COMMAND)
                ModifierKey("⌥", "Option", router, InputModifiers.OPTION)
                ModifierKey("⌃", "Control", router, InputModifiers.CONTROL)
                ModifierKey("⇧", "Shift", router, InputModifiers.SHIFT)
                Divider()
                PlainKey("Esc", "Escape", router, HidKeys.ESCAPE)
                PlainKey("Tab", "Tab", router, HidKeys.TAB)
                Divider()
                PlainKey("←", "Mũi tên trái", router, HidKeys.LEFT)
                PlainKey("↓", "Mũi tên xuống", router, HidKeys.DOWN)
                PlainKey("↑", "Mũi tên lên", router, HidKeys.UP)
                PlainKey("→", "Mũi tên phải", router, HidKeys.RIGHT)
            }
            Divider()
            Key("Ẩn", "Ẩn bàn phím", State.OFF, null, Modifier.padding(horizontal = 4.dp), onHide)
        }
    }
}

@Composable
private fun Divider() = Box(Modifier.padding(horizontal = 2.dp).width(1.dp).height(24.dp).background(XdeskOverlay.divider))

@Composable
private fun PlainKey(label: String, name: String, router: StreamInputRouter, usage: Int) =
    Key(label, name, State.OFF, null, onClick = { router.tapAccessoryKey(usage) })

@Composable
private fun ModifierKey(label: String, name: String, router: StreamInputRouter, bit: Int) =
    Key(label, name, router.modifiers.state(bit), "Chạm một lần cho phím kế tiếp, chạm hai lần để khoá", onClick = { router.tapModifier(bit) })

@Composable
private fun Key(label: String, name: String, state: State, hint: String?, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val shape = RoundedCornerShape(8.dp)
    val haptic = LocalHapticFeedback.current
    var previous by remember { mutableStateOf(state) }
    LaunchedEffect(state) {
        if (state == State.LOCKED && previous != State.LOCKED) haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        previous = state
    }
    val description = hint ?: ""
    Box(
        modifier
            .sizeIn(minWidth = 48.dp, minHeight = 48.dp)
            .padding(2.dp)
            .background(if (state == State.LOCKED) XdeskOverlay.accent else if (state == State.ARMED) XdeskOverlay.accent.copy(alpha = 0.5f) else XdeskOverlay.key, shape)
            .border(if (state == State.OFF) 1.dp else 2.dp, if (state == State.OFF) XdeskOverlay.outline else XdeskOverlay.content, shape)
            .clickable(onClickLabel = name, onClick = onClick)
            .semantics {
                role = Role.Button
                contentDescription = name
                if (hint != null) {
                    selected = state != State.OFF
                    stateDescription = when (state) { State.OFF -> "Tắt"; State.ARMED -> "Áp cho phím kế tiếp"; State.LOCKED -> "Đã khoá" } + ". $description"
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = XdeskOverlay.content, fontSize = 18.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 6.dp))
    }
}
