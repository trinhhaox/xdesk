package vn.xox.xdesk.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.PointerId
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.input.KeyRect
import vn.xox.xdesk.app.input.KeyboardGeometryCalculator
import vn.xox.xdesk.app.input.MacKey
import vn.xox.xdesk.app.input.MacKeyLayout
import vn.xox.xdesk.app.input.MacKeyboardEngine.ModState
import vn.xox.xdesk.app.input.MacKeyboardSnapshot
import vn.xox.xdesk.app.ui.theme.XdeskOverlay

/**
 * Một phím: phản hồi ngay khi chạm xuống ([onDown]) và nhả khi ngón rời ([onUp]). Mỗi phím có `pointerInput` riêng
 * nên nhiều ngón (giữ ⌘ + bấm C) chạy song song; ngón trượt ra ngoài phím vẫn tính là còn giữ phím đó.
 */
@Composable
internal fun MacKeyCap(rect: KeyRect, snapshot: MacKeyboardSnapshot, fnActive: Boolean, onDown: () -> Unit, onUp: () -> Unit) {
    val key = rect.key
    val down by rememberUpdatedState(onDown)
    val up by rememberUpdatedState(onUp)
    val modState = snapshot.modState(key.usage)
    val lit = (key.kind == MacKey.Kind.FN && fnActive) || key.usage in snapshot.pressed || modState != ModState.OFF || (key.kind == MacKey.Kind.CAPS_LOCK && snapshot.capsLock)
    val label = MacKeyLayout.displayLabel(key, snapshot.shiftActive, snapshot.capsLock)
    Box(
        modifier = Modifier
            .offset(rect.x.dp, rect.y.dp)
            .size(rect.width.dp, rect.height.dp)
            .clip(RoundedCornerShape(6.dp))
            .background(if (lit) XdeskOverlay.accent else XdeskOverlay.key)
            .then(if (modState == ModState.LOCKED) Modifier.border(2.dp, XdeskOverlay.accentLight, RoundedCornerShape(6.dp)) else Modifier)
            .semantics { contentDescription = key.label.ifBlank { "space" } }
            .pointerInput(key.usage) {
                awaitEachGesture {
                    // Mọi ngón trên phím này đều tính: ngón mới khi đang giữ = nhả rồi nhấn lại (gõ "ll" bằng hai ngón luân phiên).
                    val active = mutableSetOf<PointerId>()
                    val first = awaitFirstDown(requireUnconsumed = false)
                    first.consume()
                    active += first.id
                    down()
                    try {
                        while (active.isNotEmpty()) {
                            for (change in awaitPointerEvent().changes) {
                                when {
                                    change.id in active && !change.pressed -> { active -= change.id; change.consume() }
                                    change.id in active -> change.consume()
                                    change.pressed && !change.previousPressed -> { active += change.id; change.consume(); up(); down() }
                                }
                            }
                        }
                    } finally {
                        up()
                    }
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        val size = KeyboardGeometryCalculator.labelFontSp(label, rect.width, rect.height)
        Text(
            label,
            color = XdeskOverlay.content,
            fontSize = size.sp,
            fontWeight = FontWeight.Medium,
            textAlign = TextAlign.Center,
            maxLines = 2,
            softWrap = false,
        )
        if (key.kind == MacKey.Kind.CAPS_LOCK) {
            Box(
                Modifier.align(Alignment.TopStart).padding(4.dp).size(6.dp).clip(CircleShape)
                    .background(if (snapshot.capsLock) XdeskOverlay.good else XdeskOverlay.contentDisabled),
            )
        }
    }
}
