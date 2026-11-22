package vn.xox.xdesk.app.ui

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.ui.theme.XdeskOverlay
import vn.xox.xdesk.app.window.WindowAdjustState
import vn.xox.xdesk.app.window.WindowSpace
import vn.xox.xdesk.wire.WindowPreset

private val HandleSize = 28.dp
private val HandleHitRadius = 32.dp

/**
 * Lớp phủ "Chỉnh cửa sổ" trên video: nuốt mọi chạm (chuột thường và zoom video tạm tắt), vẽ khung chọn + tên app + 4 tay cầm góc,
 * gợi ý phía trên và thanh xếp nhanh phía dưới. [space] đọc toạ độ hiện hành mỗi lần vẽ/chạm để theo kịp zoom, xoay máy và bàn phím.
 */
@Composable
fun WindowAdjustOverlay(state: WindowAdjustState, space: () -> WindowSpace?) {
    val view = LocalView.current
    val windowId = state.selection?.windowId
    LaunchedEffect(windowId) { if (windowId != null) view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK) }
    LaunchedEffect(state) { while (true) withFrameNanos { state.flush(it) } }
    val hitRadius = with(LocalDensity.current) { HandleHitRadius.toPx() }

    Box(Modifier.fillMaxSize().pointerInput(state) { windowAdjustGestures(state, space, hitRadius) }) {
        FrameLayer(state, space)
        Hint(if (state.canAdjust) "Kéo để di chuyển, chụm hai ngón để đổi cỡ" else "Chạm vào cửa sổ muốn chỉnh", Modifier.align(Alignment.TopCenter))
        PresetBar(state, Modifier.align(Alignment.BottomCenter))
    }
}

@Composable
private fun FrameLayer(state: WindowAdjustState, space: () -> WindowSpace?) {
    val frame = state.frame
    val sp = space()
    if (frame == null || sp == null) return
    val rect = sp.frameToView(frame)
    val accent = XdeskOverlay.accent
    val density = LocalDensity.current
    Canvas(Modifier.fillMaxSize()) {
        val topLeft = Offset(rect.left, rect.top)
        val size = Size(rect.width, rect.height)
        drawRect(accent.copy(alpha = 0.10f), topLeft, size)
        drawRect(accent, topLeft, size, style = Stroke(width = 2.dp.toPx()))
        if (state.canResize) {
            val radius = HandleSize.toPx() / 2
            listOf(rect.left to rect.top, rect.right to rect.top, rect.left to rect.bottom, rect.right to rect.bottom).forEach { (x, y) ->
                drawCircle(Color.White, radius, Offset(x, y))
                drawCircle(accent, radius, Offset(x, y), style = Stroke(width = 2.dp.toPx()))
            }
        }
    }
    val name = state.selection?.app?.takeIf { it.isNotBlank() }
    if (name != null) {
        val labelX = with(density) { rect.left.coerceAtLeast(0f).toDp() }
        val labelY = with(density) { (rect.top - 30.dp.toPx()).coerceAtLeast(0f).toDp() }
        Text(
            name, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(start = labelX, top = labelY).background(accent, RoundedCornerShape(6.dp)).padding(horizontal = 8.dp, vertical = 3.dp),
        )
    }
}

@Composable
private fun Hint(text: String, modifier: Modifier) {
    Box(modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.safeDrawing).padding(top = 12.dp), contentAlignment = Alignment.TopCenter) {
        Text(
            text, color = XdeskOverlay.content, fontSize = 14.sp, textAlign = TextAlign.Center,
            modifier = Modifier.background(XdeskOverlay.bar, RoundedCornerShape(50)).padding(horizontal = 16.dp, vertical = 9.dp),
        )
    }
}

@Composable
private fun PresetBar(state: WindowAdjustState, modifier: Modifier) {
    val enabled = state.canAdjust
    Box(modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.safeDrawing).padding(horizontal = 8.dp, vertical = 8.dp)) {
        Row(
            Modifier.fillMaxWidth().background(XdeskOverlay.bar, RoundedCornerShape(14.dp)).padding(4.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            BarButton("Vừa màn hình", enabled, Modifier.weight(1f)) { state.applyPreset(WindowPreset.FILL) }
            BarButton("◧ Trái", enabled, Modifier.weight(1f)) { state.applyPreset(WindowPreset.LEFT) }
            BarButton("◨ Phải", enabled, Modifier.weight(1f)) { state.applyPreset(WindowPreset.RIGHT) }
            BarButton("▣ Giữa", enabled, Modifier.weight(1f)) { state.applyPreset(WindowPreset.CENTER) }
            BarButton("↺ Khôi phục", enabled, Modifier.weight(1f)) { state.applyPreset(WindowPreset.RESTORE) }
            BarButton("Xong", true, Modifier.weight(1f), XdeskOverlay.accentLight) { state.exit() }
        }
    }
}

@Composable
private fun BarButton(label: String, enabled: Boolean, modifier: Modifier, tint: Color = XdeskOverlay.content, onClick: () -> Unit) {
    Box(
        modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(10.dp))
            .clickable(enabled = enabled, onClick = onClick).semantics { role = Role.Button }.padding(horizontal = 2.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = if (enabled) tint else XdeskOverlay.contentDisabled, fontSize = 11.sp, fontWeight = FontWeight.Medium, textAlign = TextAlign.Center, maxLines = 2)
    }
}
