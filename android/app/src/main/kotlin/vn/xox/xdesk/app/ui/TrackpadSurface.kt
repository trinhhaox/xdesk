package vn.xox.xdesk.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.abs
import kotlin.math.hypot
import vn.xox.xdesk.app.ui.theme.XdeskOverlay
import vn.xox.xdesk.transport.InputButton
import vn.xox.xdesk.transport.InputModifiers

/** Các hành động con trỏ mà vùng cảm ứng phát ra; do [RemoteTrackpadSheet] nối vào controller. */
internal class TrackpadActions(
    val onMove: (Float, Float) -> Unit,
    val onClick: (Int) -> Unit,
    val onScroll: (Float, Float) -> Unit,
    val onLeftDownChange: (Boolean) -> Unit,
    val onThreeFingerShortcut: (Int, Int) -> Unit,
)

private const val DOUBLE_TAP_MS = 280L
private const val TAP_MAX_MS = 300L
private const val RIGHT_CLICK_MAX_MS = 350L
private const val HINT_MIN_HEIGHT_DP = 110

private fun nowMs() = android.os.SystemClock.uptimeMillis()

/** Vùng cảm ứng: 1 ngón di / chạm đúp giữ kéo, 2 ngón phải / cuộn, 3 ngón không gian & cửa sổ. */
@Composable
internal fun TrackpadSurface(actions: TrackpadActions, modifier: Modifier = Modifier) {
    val current by rememberUpdatedState(actions)
    var lastSingleTapUpMs by remember { mutableStateOf(0L) }
    var lastSingleTapPos by remember { mutableStateOf(Offset.Zero) }
    BoxWithConstraints(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(XdeskOverlay.bar)
            .border(1.dp, XdeskOverlay.divider, RoundedCornerShape(16.dp))
            .pointerInput(Unit) {
                val slopPx = viewConfiguration.touchSlop
                val tapSlopRadiusPx = 24f * density
                val threeFingerThresholdPx = 42f * density
                awaitEachGesture {
                    val firstDown = awaitFirstDown(requireUnconsumed = false)
                    val startTime = firstDown.uptimeMillis
                    var maxPointers = 1
                    var totalMoved = 0f
                    var movedBeyondSlop = false
                    var tapDragArmed = (startTime - lastSingleTapUpMs <= DOUBLE_TAP_MS) &&
                        hypot(firstDown.position.x - lastSingleTapPos.x, firstDown.position.y - lastSingleTapPos.y) <= tapSlopRadiusPx
                    var tapDragActive = false
                    var threeFingerDx = 0f
                    var threeFingerDy = 0f
                    var threeFingerFired = false
                    var lastSinglePos = firstDown.position
                    var previousPositions = mapOf(firstDown.id to firstDown.position)

                    while (true) {
                        val event = awaitPointerEvent()
                        val pressed = event.changes.filter { it.pressed }
                        maxPointers = maxOf(maxPointers, pressed.size, event.changes.size)
                        if (maxPointers > 1) tapDragArmed = false
                        if (pressed.isEmpty()) break
                        if (pressed.size == 1) lastSinglePos = pressed.first().position

                        var sumDx = 0f
                        var sumDy = 0f
                        for (change in pressed) {
                            val prev = previousPositions[change.id] ?: change.previousPosition
                            sumDx += change.position.x - prev.x
                            sumDy += change.position.y - prev.y
                        }
                        val avgDx = sumDx / pressed.size
                        val avgDy = sumDy / pressed.size
                        val step = hypot(avgDx, avgDy)
                        totalMoved += step
                        if (totalMoved > slopPx) movedBeyondSlop = true
                        if (movedBeyondSlop && step > 0f) {
                            pressed.forEach { it.consume() }
                            if (maxPointers >= 3) {
                                if (!threeFingerFired) {
                                    threeFingerDx += avgDx
                                    threeFingerDy += avgDy
                                    if (hypot(threeFingerDx, threeFingerDy) >= threeFingerThresholdPx) {
                                        threeFingerFired = true
                                        if (abs(threeFingerDy) >= abs(threeFingerDx)) {
                                            current.onThreeFingerShortcut(if (threeFingerDy < 0f) 0x52 else 0x51, InputModifiers.CONTROL)
                                        } else {
                                            current.onThreeFingerShortcut(if (threeFingerDx < 0f) 0x4F else 0x50, InputModifiers.CONTROL)
                                        }
                                    }
                                }
                            } else if (pressed.size >= 2 || maxPointers >= 2) {
                                val dpScale = 1.4f / density
                                current.onScroll(avgDx * dpScale, avgDy * dpScale)
                            } else {
                                if (tapDragArmed && !tapDragActive) {
                                    tapDragActive = true
                                    current.onLeftDownChange(true)
                                }
                                val sensitivity = 0.0018f
                                current.onMove(avgDx * sensitivity, avgDy * sensitivity)
                            }
                        }
                        previousPositions = pressed.associate { it.id to it.position }
                    }

                    if (tapDragActive) {
                        current.onLeftDownChange(false)
                    } else if (!movedBeyondSlop) {
                        val duration = (nowMs() - startTime).coerceAtLeast(0L)
                        if (maxPointers >= 2 && duration <= RIGHT_CLICK_MAX_MS) {
                            current.onClick(InputButton.RIGHT)
                        } else if (maxPointers == 1 && duration <= TAP_MAX_MS) {
                            lastSingleTapUpMs = nowMs()
                            lastSingleTapPos = lastSinglePos
                            current.onClick(InputButton.LEFT)
                        }
                    }
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        val showHint = maxHeight.value >= HINT_MIN_HEIGHT_DP
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(horizontal = 12.dp)) {
            Icon(XdeskIcons.Mouse, contentDescription = null, tint = XdeskOverlay.contentMuted.copy(alpha = 0.55f), modifier = Modifier.size(28.dp))
            if (showHint) {
                Spacer(Modifier.height(4.dp))
                Text("Bàn di chuột cảm ứng", color = XdeskOverlay.contentMuted, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                Text(
                    "1 ngón: Di chuột · Chạm đúp giữ: Kéo thả\n2 ngón: Chuột phải / Cuộn · 3 ngón: Không gian & Cửa sổ",
                    color = XdeskOverlay.contentMuted.copy(alpha = 0.7f), fontSize = 11.sp, textAlign = TextAlign.Center, lineHeight = 16.sp,
                )
            }
        }
    }
}
