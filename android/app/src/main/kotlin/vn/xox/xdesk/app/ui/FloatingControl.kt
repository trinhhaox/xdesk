package vn.xox.xdesk.app.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import vn.xox.xdesk.app.FloatingControlStore
import vn.xox.xdesk.app.FloatingPlacement

private val ButtonSize = 48.dp
private const val IDLE_MS = 3000L
private const val EXPANDED_MS = 8000L

class FloatingAction(val label: String, val description: String = label, val enabled: Boolean = true, val onClick: () -> Unit)

/**
 * Một nút nổi 48 dp thay thanh công cụ cố định (thanh cũ che biểu tượng trạng thái trên menu bar Mac). Chạm mở menu gọn; kéo rồi thả thì
 * dính mép trái/phải gần nhất (vị trí được lưu); mờ còn 35% sau 3 s không chạm. Chỉ nút và menu nhận chạm; phần còn lại của container
 * không có pointerInput nên chạm xuyên xuống video.
 */
@Composable
fun FloatingControl(store: FloatingControlStore, status: String, actions: List<FloatingAction>, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.fillMaxSize()) {
        val density = LocalDensity.current
        val size = with(density) { ButtonSize.toPx() }
        val margin = with(density) { 4.dp.toPx() }
        val width = constraints.maxWidth.toFloat()
        val height = constraints.maxHeight.toFloat()
        var expanded by remember { mutableStateOf(false) }
        var drag by remember { mutableStateOf<Offset?>(null) }
        var activity by remember { mutableIntStateOf(0) }
        var idle by remember { mutableStateOf(false) }
        var menuSize by remember { mutableStateOf(androidx.compose.ui.unit.IntSize.Zero) }
        LaunchedEffect(activity, expanded) {
            idle = false
            delay(if (expanded) EXPANDED_MS else IDLE_MS)
            if (expanded) expanded = false else idle = true
        }
        val (rx, ry) = store.placement.origin(width, height, size, margin)
        val at = drag ?: Offset(rx, ry)
        val alpha by animateFloatAsState(if (idle) 0.35f else 1f, label = "floating-fade")

        if (expanded) {
            val menuX = if (store.placement.trailing) at.x - menuSize.width - margin * 2 else at.x + size + margin * 2
            val menuY = at.y.coerceIn(margin, maxOf(margin, height - menuSize.height - margin))
            Column(
                Modifier.offset { IntOffset(menuX.roundToInt(), menuY.roundToInt()) }.width(240.dp).onSizeChanged { menuSize = it }
                    .background(Color(0xCC000000), RoundedCornerShape(14.dp)).padding(6.dp),
            ) {
                if (status.isNotBlank()) Text(status, color = Color(0xB3FFFFFF), modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
                actions.forEach { a ->
                    TextButton(
                        onClick = { a.onClick(); expanded = false; activity++ }, enabled = a.enabled,
                        modifier = Modifier.heightIn(min = 48.dp).semantics { contentDescription = a.description },
                    ) { Text(a.label, color = Color.White, modifier = Modifier.width(220.dp)) }
                }
            }
        }
        Text(
            if (expanded) "✕" else "⋯", color = Color.White, textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            modifier = Modifier
                .offset { IntOffset(at.x.roundToInt(), at.y.roundToInt()) }
                .size(ButtonSize).graphicsLayer { this.alpha = alpha }
                .background(Color(0x99000000), CircleShape).padding(top = 12.dp)
                .pointerInput(Unit) { detectTapGestures(onTap = { expanded = !expanded; activity++ }) }
                .pointerInput(width, height) {
                    var current = Offset.Zero
                    detectDragGestures(
                        onDragStart = { expanded = false; activity++; current = Offset(rx, ry).also { drag = it } },
                        onDrag = { change, delta -> change.consume(); current += delta; drag = current },
                        onDragEnd = {
                            store.save(FloatingPlacement.snapped(current.x + size / 2, current.y + size / 2, width, height, size))
                            drag = null; activity++
                        },
                        onDragCancel = { drag = null },
                    )
                }
                .semantics {
                    contentDescription = if (expanded) "Đóng menu điều khiển" else "Điều khiển Xdesk: ngắt kết nối, bàn phím, chuột"
                    role = Role.Button
                    onClick { expanded = !expanded; activity++; true }
                },
        )
    }
}
