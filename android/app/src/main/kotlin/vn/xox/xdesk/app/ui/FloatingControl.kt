package vn.xox.xdesk.app.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
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
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import vn.xox.xdesk.app.DisplaySettingsStore
import vn.xox.xdesk.app.FloatingControlStore
import vn.xox.xdesk.app.FloatingPlacement
import vn.xox.xdesk.app.WorkMode
import vn.xox.xdesk.app.ui.theme.XdeskOverlay
import vn.xox.xdesk.wire.MirrorFit

private val ButtonSize = 48.dp
private val Panel = XdeskOverlay.panel
private val Outline = XdeskOverlay.outline
private val PanelOutline = Color.White.copy(alpha = 0.35f)
private const val IDLE_ALPHA = 0.7f
private const val IDLE_MS = 3000L
private const val EXPANDED_MS = 8000L

class FloatingAction(
    val label: String,
    val icon: ImageVector,
    val description: String = label,
    val enabled: Boolean = true,
    val isDestructive: Boolean = false,
    val afterShortcuts: Boolean = false,
    val trailingIcon: ImageVector? = null,
    val trailingDescription: String? = null,
    val onTrailingClick: (() -> Unit)? = null,
    val onClick: () -> Unit,
)

class DockShortcut(
    val label: String,
    val icon: ImageVector,
    val description: String = label,
    val enabled: Boolean = true,
    val onClick: () -> Unit,
)

/**
 * Một nút nổi 48 dp thay thanh công cụ cố định (thanh cũ che biểu tượng trạng thái trên menu bar Mac): đĩa đặc tối, chữ trắng, viền sáng
 * và bóng nên đọc được trên mọi nền Mac. Chạm mở menu 3 tầng (thao tác nhanh 4 nút, điều khiển/phím tắt Mac, ngắt kết nối dưới đáy).
 */
@Composable
fun FloatingControl(
    store: FloatingControlStore,
    status: String,
    activeWorkMode: WorkMode,
    onSelectWorkMode: (WorkMode) -> Unit,
    actions: List<FloatingAction>,
    quickDock: List<DockShortcut> = emptyList(),
    macShortcuts: List<DockShortcut> = emptyList(),
    activeMirrorFit: MirrorFit? = null,
    onSelectMirrorFit: (MirrorFit) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    BoxWithConstraints(modifier.fillMaxSize()) {
        val density = LocalDensity.current
        val size = with(density) { ButtonSize.toPx() }
        val margin = with(density) { 4.dp.toPx() }
        val width = constraints.maxWidth.toFloat()
        val height = constraints.maxHeight.toFloat()
        var expanded by remember { mutableStateOf(false) }
        var shortcutsOpen by remember { mutableStateOf(false) }
        var fitOpen by remember { mutableStateOf(false) }
        var drag by remember { mutableStateOf<Offset?>(null) }
        var activity by remember { mutableIntStateOf(0) }
        var idle by remember { mutableStateOf(false) }
        var menuSize by remember { mutableStateOf(IntSize.Zero) }
        LaunchedEffect(expanded) {
            if (!expanded) {
                shortcutsOpen = false
                fitOpen = false
            }
        }
        LaunchedEffect(activity, expanded) {
            idle = false
            delay(if (expanded) EXPANDED_MS else IDLE_MS)
            if (expanded) expanded = false else idle = true
        }
        val (rx, ry) = store.placement.origin(width, height, size, margin)
        val at = drag ?: Offset(rx, ry)
        val alpha by animateFloatAsState(if (idle && !expanded) IDLE_ALPHA else 1f, label = "floating-fade")

        if (expanded) {
            val menuMargin = with(density) { 12.dp.toPx() }
            val (menuX, menuY) = store.placement.menuOrigin(at.x, at.y, size, menuSize.width.toFloat(), menuSize.height.toFloat(), menuMargin, width, height)
            val (primaryActions, destructiveActions) = actions.partition { !it.isDestructive }
            val (afterShortcutActions, beforeShortcutActions) = primaryActions.partition { it.afterShortcuts }
            Column(
                Modifier.offset { IntOffset(menuX.roundToInt(), menuY.roundToInt()) }.width(276.dp).heightIn(max = with(density) { (height - menuMargin * 2).toDp() })
                    .onSizeChanged { menuSize = it }
                    .shadow(8.dp, RoundedCornerShape(14.dp)).background(Panel, RoundedCornerShape(14.dp)).border(1.dp, PanelOutline, RoundedCornerShape(14.dp))
                    .verticalScroll(rememberScrollState()).padding(6.dp),
            ) {
                if (status.isNotBlank()) {
                    Text(
                        status, color = XdeskOverlay.contentMuted, fontSize = 11.sp,
                        maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    )
                }
                Text(
                    "Chế độ làm việc",
                    color = XdeskOverlay.contentMuted,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                )
                WorkModeSwitcher(
                    activeMode = activeWorkMode,
                    onSelectMode = { mode ->
                        onSelectWorkMode(mode)
                        expanded = false
                        activity++
                    },
                    modifier = Modifier.padding(horizontal = 2.dp, vertical = 4.dp),
                )
                if (quickDock.isNotEmpty()) {
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = 2.dp, vertical = 4.dp).background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(10.dp)).padding(vertical = 4.dp, horizontal = 2.dp),
                        horizontalArrangement = Arrangement.spacedBy(2.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        quickDock.forEach { s ->
                            val tileTint = if (s.enabled) XdeskOverlay.content else XdeskOverlay.contentDisabled
                            Column(
                                Modifier.weight(1f).heightIn(min = 56.dp)
                                    .pointerInput(s) { detectTapGestures(onTap = { if (s.enabled) { s.onClick(); expanded = false; activity++ } }) }
                                    .semantics { contentDescription = s.description; role = Role.Button; onClick { if (s.enabled) { s.onClick(); expanded = false; activity++ }; true } },
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.Center,
                            ) {
                                Box(
                                    Modifier.size(34.dp).background(Color.White.copy(alpha = if (s.enabled) 0.12f else 0.05f), CircleShape),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Icon(s.icon, contentDescription = null, Modifier.size(18.dp), tint = tileTint)
                                }
                                Spacer(Modifier.size(3.dp))
                                Text(s.label, color = tileTint, fontSize = 11.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
                            }
                        }
                    }
                    HorizontalDivider(Modifier.padding(vertical = 4.dp), color = XdeskOverlay.divider)
                } else {
                    HorizontalDivider(Modifier.padding(vertical = 4.dp), color = XdeskOverlay.divider)
                }
                beforeShortcutActions.forEach { a ->
                    FloatingActionRow(a, XdeskOverlay.content) {
                        expanded = false
                        activity++
                    }
                }
                activeMirrorFit?.let { currentFit ->
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 48.dp)
                            .pointerInput(currentFit) {
                                detectTapGestures(onTap = {
                                    fitOpen = !fitOpen
                                    if (fitOpen) shortcutsOpen = false
                                    activity++
                                })
                            }
                            .semantics {
                                contentDescription = "Kiểu chiếu: ${currentFit.title()}"
                                role = Role.Button
                                onClick {
                                    fitOpen = !fitOpen
                                    if (fitOpen) shortcutsOpen = false
                                    activity++
                                    true
                                }
                            }
                            .padding(horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(currentFit.icon(), contentDescription = null, Modifier.size(20.dp), tint = XdeskOverlay.content)
                        Text(
                            "Kiểu chiếu: ${currentFit.title()}",
                            color = XdeskOverlay.content,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Medium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f).padding(start = 10.dp),
                        )
                        Icon(
                            XdeskIcons.Chevron,
                            contentDescription = if (fitOpen) "Thu gọn" else "Mở rộng",
                            Modifier.size(16.dp).rotate(if (fitOpen) 90f else 0f),
                            tint = XdeskOverlay.contentMuted,
                        )
                    }
                    if (fitOpen) {
                        Column(
                            Modifier.fillMaxWidth().padding(start = 10.dp, end = 4.dp, bottom = 4.dp)
                                .background(Color.White.copy(alpha = 0.06f), RoundedCornerShape(10.dp))
                                .padding(4.dp),
                            verticalArrangement = Arrangement.spacedBy(2.dp),
                        ) {
                            DisplaySettingsStore.SUPPORTED_FITS.forEach { option ->
                                val selected = option == currentFit
                                Row(
                                    Modifier.fillMaxWidth().heightIn(min = 44.dp)
                                        .background(
                                            if (selected) XdeskOverlay.accent.copy(alpha = 0.22f) else Color.Transparent,
                                            RoundedCornerShape(8.dp),
                                        )
                                        .pointerInput(option, currentFit) {
                                            detectTapGestures(onTap = {
                                                if (option != currentFit) onSelectMirrorFit(option)
                                                expanded = false
                                                activity++
                                            })
                                        }
                                        .semantics {
                                            contentDescription = option.title()
                                            role = Role.Button
                                            onClick {
                                                if (option != currentFit) onSelectMirrorFit(option)
                                                expanded = false
                                                activity++
                                                true
                                            }
                                        }
                                        .padding(horizontal = 10.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Icon(
                                        option.icon(),
                                        contentDescription = null,
                                        Modifier.size(18.dp),
                                        tint = if (selected) XdeskOverlay.accentLight else XdeskOverlay.contentMuted,
                                    )
                                    Text(
                                        option.title(),
                                        color = XdeskOverlay.content,
                                        fontSize = 14.sp,
                                        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                        modifier = Modifier.weight(1f).padding(start = 10.dp),
                                    )
                                    if (selected) {
                                        Icon(
                                            Icons.Filled.Check,
                                            contentDescription = "Đang chọn",
                                            Modifier.size(16.dp),
                                            tint = XdeskOverlay.accentLight,
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                if (macShortcuts.isNotEmpty()) {
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 48.dp)
                            .pointerInput(Unit) {
                                detectTapGestures(onTap = {
                                    shortcutsOpen = !shortcutsOpen
                                    if (shortcutsOpen) fitOpen = false
                                    activity++
                                })
                            }
                            .semantics {
                                contentDescription = "Phím tắt Mac"
                                role = Role.Button
                                onClick {
                                    shortcutsOpen = !shortcutsOpen
                                    if (shortcutsOpen) fitOpen = false
                                    activity++
                                    true
                                }
                            }
                            .padding(horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(XdeskIcons.Layers, contentDescription = null, Modifier.size(20.dp), tint = XdeskOverlay.content)
                        Text("Phím tắt Mac", color = XdeskOverlay.content, fontSize = 15.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f).padding(start = 10.dp))
                        Icon(
                            XdeskIcons.Chevron,
                            contentDescription = if (shortcutsOpen) "Thu gọn" else "Mở rộng",
                            Modifier.size(16.dp).rotate(if (shortcutsOpen) 90f else 0f),
                            tint = XdeskOverlay.contentMuted,
                        )
                    }
                    if (shortcutsOpen) {
                        Column(
                            Modifier.fillMaxWidth().padding(start = 10.dp, end = 4.dp, bottom = 4.dp)
                                .background(Color.White.copy(alpha = 0.06f), RoundedCornerShape(10.dp)),
                        ) {
                            macShortcuts.forEach { s ->
                                Row(
                                    Modifier.fillMaxWidth().heightIn(min = 44.dp)
                                        .pointerInput(s) { detectTapGestures(onTap = { s.onClick(); expanded = false; activity++ }) }
                                        .semantics { contentDescription = s.description; role = Role.Button; onClick { s.onClick(); expanded = false; activity++; true } }
                                        .padding(horizontal = 10.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Icon(s.icon, contentDescription = null, Modifier.size(18.dp), tint = XdeskOverlay.contentMuted)
                                    Text(s.label, color = XdeskOverlay.content, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 10.dp))
                                }
                            }
                        }
                    }
                }
                afterShortcutActions.forEach { a ->
                    FloatingActionRow(a, XdeskOverlay.content) {
                        expanded = false
                        activity++
                    }
                }
                if (destructiveActions.isNotEmpty()) {
                    HorizontalDivider(Modifier.padding(vertical = 4.dp), color = XdeskOverlay.divider)
                    destructiveActions.forEach { a ->
                        FloatingActionRow(a, XdeskOverlay.danger) {
                            expanded = false
                            activity++
                        }
                    }
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
        ) { Icon(if (expanded) Icons.Filled.Close else XdeskIcons.Ellipsis, contentDescription = null, tint = XdeskOverlay.content, modifier = Modifier.size(24.dp)) }
    }
}

@Composable
private fun FloatingActionRow(action: FloatingAction, baseTint: Color, onClose: () -> Unit) {
    val tint = if (action.enabled) baseTint else XdeskOverlay.contentDisabled
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
        Row(
            Modifier.weight(1f).heightIn(min = 48.dp)
                .pointerInput(action) { detectTapGestures(onTap = { if (action.enabled) { action.onClick(); onClose() } }) }
                .semantics { contentDescription = action.description; role = Role.Button; onClick { if (action.enabled) { action.onClick(); onClose() }; true } }
                .padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(action.icon, contentDescription = null, Modifier.size(20.dp), tint = tint)
            Text(action.label, color = tint, fontSize = 15.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 10.dp))
        }
        val trailingIcon = action.trailingIcon
        val onTrailingClick = action.onTrailingClick
        if (trailingIcon != null && onTrailingClick != null) {
            Box(
                Modifier.size(44.dp).padding(2.dp)
                    .background(Color.White.copy(alpha = 0.08f), CircleShape)
                    .pointerInput(onTrailingClick) { detectTapGestures(onTap = { onTrailingClick(); onClose() }) }
                    .semantics { contentDescription = action.trailingDescription ?: action.label; role = Role.Button; onClick { onTrailingClick(); onClose(); true } },
                contentAlignment = Alignment.Center,
            ) {
                Icon(trailingIcon, contentDescription = null, Modifier.size(18.dp), tint = XdeskOverlay.contentMuted)
            }
        }
    }
}
