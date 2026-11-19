package vn.xox.xdesk.app.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import vn.xox.xdesk.app.FloatingControlStore
import vn.xox.xdesk.app.FloatingPlacement

private val ButtonSize = 48.dp
private val Panel = Color(0xFF16181F)
private val Outline = Color(0x8CFFFFFF)
private const val IDLE_ALPHA = 0.7f
private const val IDLE_MS = 3000L
private const val EXPANDED_MS = 8000L

class FloatingAction(val label: String, val description: String = label, val enabled: Boolean = true, val onClick: () -> Unit)

/**
 * Một nút nổi 48 dp thay thanh công cụ cố định (thanh cũ che biểu tượng trạng thái trên menu bar Mac): đĩa đặc tối, chữ trắng, viền sáng
 * và bóng nên đọc được trên mọi nền Mac. Chạm mở menu đặc; kéo rồi thả thì dính mép trái/phải gần nhất (vị trí được lưu); sau 3 s không chạm
 * chỉ nhạt còn 70%. Phần tử này vẽ trên khung video nên nhận chạm trước; ngoài nút và menu không có pointerInput nên chạm xuyên xuống video.
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
        var menuSize by remember { mutableStateOf(IntSize.Zero) }
        LaunchedEffect(activity, expanded) {
            idle = false
            delay(if (expanded) EXPANDED_MS else IDLE_MS)
            if (expanded) expanded = false else idle = true
        }
        val (rx, ry) = store.placement.origin(width, height, size, margin)
        val at = drag ?: Offset(rx, ry)
        val alpha by animateFloatAsState(if (idle && !expanded) IDLE_ALPHA else 1f, label = "floating-fade")

        if (expanded) {
            val (menuX, menuY) = store.placement.menuOrigin(at.x, at.y, size, menuSize.width.toFloat(), menuSize.height.toFloat(), margin * 2, width, height)
            Column(
                Modifier.offset { IntOffset(menuX.roundToInt(), menuY.roundToInt()) }.width(240.dp).heightIn(max = with(density) { (height - margin * 4).toDp() })
                    .onSizeChanged { menuSize = it }
                    .shadow(8.dp, RoundedCornerShape(14.dp)).background(Panel, RoundedCornerShape(14.dp)).border(1.dp, Outline, RoundedCornerShape(14.dp))
                    .verticalScroll(rememberScrollState()).padding(6.dp),
            ) {
                if (status.isNotBlank()) Text(status, color = Color(0xFFC8CCD8), fontSize = 12.sp, modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp))
                actions.forEach { a ->
                    Box(
                        Modifier.fillMaxWidth().heightIn(min = 48.dp)
                            .pointerInput(a) { detectTapGestures(onTap = { if (a.enabled) { a.onClick(); expanded = false; activity++ } }) }
                            .semantics { contentDescription = a.description; role = Role.Button; onClick { if (a.enabled) { a.onClick(); expanded = false; activity++ }; true } },
                        contentAlignment = Alignment.CenterStart,
                    ) { Text(a.label, color = if (a.enabled) Color.White else Color(0x80FFFFFF), fontSize = 16.sp, fontWeight = FontWeight.Medium, modifier = Modifier.padding(horizontal = 12.dp)) }
                }
            }
        }
        Box(
            Modifier
                .offset { IntOffset(at.x.roundToInt(), at.y.roundToInt()) }
                .size(ButtonSize).graphicsLayer { this.alpha = alpha }
                .shadow(6.dp, CircleShape).background(Panel, CircleShape).border(1.5.dp, Outline, CircleShape)
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
            contentAlignment = Alignment.Center,
        ) { Text(if (expanded) "✕" else "⋯", color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold) }
    }
}
