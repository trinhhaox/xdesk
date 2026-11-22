package vn.xox.xdesk.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.hypot
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.WorkMode
import vn.xox.xdesk.app.ui.theme.XdeskOverlay
import vn.xox.xdesk.transport.InputButton
import vn.xox.xdesk.transport.InputEvents
import vn.xox.xdesk.transport.InputModifiers
import vn.xox.xdesk.wire.MediaKeyKind

@Composable
fun RemoteTrackpadSheet(
    controller: ViewerController,
    activeMode: WorkMode,
    onSelectMode: (WorkMode) -> Unit,
    isFullscreen: Boolean = false,
    modifier: Modifier = Modifier,
    onDismiss: () -> Unit
) {
    var cursorX by remember { mutableFloatStateOf(0.5f) }
    var cursorY by remember { mutableFloatStateOf(0.5f) }
    var activeMods by remember { mutableIntStateOf(0) }
    var inputText by remember { mutableStateOf("") }
    var isLeftDown by remember { mutableStateOf(false) }
    var isRightDown by remember { mutableStateOf(false) }

    fun sendPointerMove(newX: Float, newY: Float) {
        val clampedX = newX.coerceIn(0.001f, 0.999f)
        val clampedY = newY.coerceIn(0.001f, 0.999f)
        cursorX = clampedX
        cursorY = clampedY
        controller.sendInput(listOf(InputEvents.move(clampedX, clampedY, activeMods)))
    }

    fun sendPointerClick(button: Int) {
        val down = InputEvents.button(down = true, x = cursorX, y = cursorY, button = button, mods = activeMods)
        val up = InputEvents.button(down = false, x = cursorX, y = cursorY, button = button, mods = activeMods)
        controller.sendInput(listOf(down, up))
    }

    fun sendPointerButtonState(button: Int, down: Boolean) {
        val event = InputEvents.button(down = down, x = cursorX, y = cursorY, button = button, mods = activeMods)
        controller.sendInput(listOf(event))
    }

    fun sendScroll(dx: Float, dy: Float) {
        controller.sendInput(listOf(InputEvents.scroll(dx, dy, activeMods)))
    }

    fun sendKey(usage: Int, extraMods: Int = 0) {
        val mods = activeMods or extraMods
        controller.sendInput(
            listOf(
                InputEvents.key(usage, true, mods),
                InputEvents.key(usage, false, mods),
            )
        )
    }

    fun sendTextDirect(text: String) {
        if (text.isNotEmpty()) {
            controller.sendText(text)
        }
    }

    Column(
        modifier = if (isFullscreen) {
            modifier
                .fillMaxSize()
                .background(XdeskOverlay.panel)
                .safeDrawingPadding()
                .padding(top = 4.dp, bottom = 12.dp)
        } else {
            modifier
                .fillMaxWidth()
                .background(XdeskOverlay.panel)
                .padding(top = 8.dp, bottom = 16.dp)
        }
    ) {
        // Tier 1: Tên máy Mac + Khoá / Ngắt kết nối
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                controller.progress.targetName.ifBlank { "Điều khiển Mac" },
                modifier = Modifier.weight(1f).padding(end = 8.dp),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                color = XdeskOverlay.content,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
            )

            Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { controller.sendSystemLock() }) {
                    Icon(
                        imageVector = XdeskIcons.Lock,
                        contentDescription = "Khóa Mac",
                        tint = XdeskOverlay.content,
                    )
                }
                IconButton(onClick = onDismiss) {
                    Icon(
                        imageVector = if (isFullscreen) XdeskIcons.Stop else XdeskIcons.Chevron,
                        contentDescription = if (isFullscreen) "Ngắt kết nối" else "Đóng",
                        tint = if (isFullscreen) XdeskOverlay.danger else XdeskOverlay.content,
                    )
                }
            }
        }

        // Tier 2: Bộ chọn 5 chế độ làm việc thống nhất (2+3)
        WorkModeSwitcher(
            activeMode = activeMode,
            onSelectMode = onSelectMode,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
        )
        HorizontalDivider(color = XdeskOverlay.divider)

        Spacer(Modifier.height(10.dp))

        when (activeMode) {
            WorkMode.TRACKPAD -> {
                TrackpadTabContent(
                    isFullscreen = isFullscreen,
                    isLeftDown = isLeftDown,
                    isRightDown = isRightDown,
                    onMove = { dx, dy -> sendPointerMove(cursorX + dx, cursorY + dy) },
                    onClick = { button -> sendPointerClick(button) },
                    onScroll = { dx, dy -> sendScroll(dx, dy) },
                    onLeftDownChange = { down ->
                        isLeftDown = down
                        sendPointerButtonState(InputButton.LEFT, down)
                    },
                    onRightDownChange = { down ->
                        isRightDown = down
                        sendPointerButtonState(InputButton.RIGHT, down)
                    },
                    onThreeFingerShortcut = { usage, mods -> sendKey(usage, mods) },
                )
            }
            WorkMode.KEYBOARD -> {
                KeyboardTabContent(
                    activeMods = activeMods,
                    inputText = inputText,
                    onInputTextChange = { inputText = it },
                    onSendText = {
                        sendTextDirect(inputText)
                        inputText = ""
                    },
                    onToggleMod = { bit ->
                        activeMods = if ((activeMods and bit) != 0) activeMods and bit.inv() else activeMods or bit
                    },
                    onKey = { usage, extraMods -> sendKey(usage, extraMods) }
                )
            }
            WorkMode.NUMPAD_MEDIA -> {
                NumpadMediaTabContent(
                    onKey = { usage, extraMods -> sendKey(usage, extraMods) },
                    onMediaKey = { kind -> controller.sendMediaKey(kind) },
                    onSendText = { char -> sendTextDirect(char) }
                )
            }
            WorkMode.MIRROR, WorkMode.EXTEND -> Unit
        }
    }
}

@Composable
private fun ColumnScope.TrackpadTabContent(
    isFullscreen: Boolean = false,
    isLeftDown: Boolean,
    isRightDown: Boolean,
    onMove: (Float, Float) -> Unit,
    onClick: (Int) -> Unit,
    onScroll: (Float, Float) -> Unit,
    onLeftDownChange: (Boolean) -> Unit,
    onRightDownChange: (Boolean) -> Unit,
    onThreeFingerShortcut: (Int, Int) -> Unit,
) {
    val containerModifier = if (isFullscreen) {
        Modifier
            .fillMaxWidth()
            .weight(1f)
            .padding(horizontal = 16.dp)
    } else {
        Modifier
            .fillMaxWidth()
            .height(340.dp)
            .padding(horizontal = 16.dp)
    }
    Column(
        modifier = containerModifier,
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        var lastSingleTapUpMs by remember { mutableStateOf(0L) }
        var lastSingleTapPos by remember { mutableStateOf(androidx.compose.ui.geometry.Offset.Zero) }
        // Vùng cảm ứng Trackpad (1 ngón di / chạm đúp giữ kéo, 2 ngón phải / cuộn, 3 ngón không gian & cửa sổ)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
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
                        var tapDragArmed = (startTime - lastSingleTapUpMs <= 280L) &&
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
                            var deltaCount = 0
                            for (change in pressed) {
                                val prev = previousPositions[change.id] ?: change.previousPosition
                                sumDx += change.position.x - prev.x
                                sumDy += change.position.y - prev.y
                                deltaCount++
                            }
                            if (deltaCount > 0) {
                                val avgDx = sumDx / deltaCount
                                val avgDy = sumDy / deltaCount
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
                                                if (kotlin.math.abs(threeFingerDy) >= kotlin.math.abs(threeFingerDx)) {
                                                    onThreeFingerShortcut(if (threeFingerDy < 0f) 0x52 else 0x51, InputModifiers.CONTROL)
                                                } else {
                                                    onThreeFingerShortcut(if (threeFingerDx < 0f) 0x4F else 0x50, InputModifiers.CONTROL)
                                                }
                                            }
                                        }
                                    } else if (pressed.size >= 2 || maxPointers >= 2) {
                                        val dpScale = 1.4f / density
                                        onScroll(avgDx * dpScale, avgDy * dpScale)
                                    } else {
                                        if (tapDragArmed && !tapDragActive) {
                                            tapDragActive = true
                                            onLeftDownChange(true)
                                        }
                                        val sensitivity = 0.0018f
                                        onMove(avgDx * sensitivity, avgDy * sensitivity)
                                    }
                                }
                            }
                            previousPositions = pressed.associate { it.id to it.position }
                        }

                        if (tapDragActive) {
                            onLeftDownChange(false)
                        } else if (!movedBeyondSlop) {
                            val duration = eventDurationMs(startTime)
                            if (maxPointers >= 2 && duration <= 350L) {
                                onClick(InputButton.RIGHT)
                            } else if (maxPointers == 1 && duration <= 300L) {
                                lastSingleTapUpMs = android.os.SystemClock.uptimeMillis()
                                lastSingleTapPos = lastSinglePos
                                onClick(InputButton.LEFT)
                            }
                        }
                    }
                },
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(horizontal = 16.dp)) {
                Icon(
                    imageVector = XdeskIcons.Mouse,
                    contentDescription = null,
                    tint = XdeskOverlay.contentMuted.copy(alpha = 0.55f),
                    modifier = Modifier.size(34.dp)
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    "Bàn di chuột cảm ứng",
                    color = XdeskOverlay.contentMuted,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    "1 ngón: Di chuột · Chạm đúp giữ: Kéo thả\n2 ngón: Chuột phải / Cuộn · 3 ngón: Không gian & Cửa sổ",
                    color = XdeskOverlay.contentMuted.copy(alpha = 0.7f),
                    fontSize = 11.sp,
                    textAlign = TextAlign.Center,
                    lineHeight = 16.sp,
                )
            }
        }

        // Hai nút chuột vật lý dưới đáy (cân bằng 50/50 như iOS)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Button(
                onClick = { onClick(InputButton.LEFT) },
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight(),
                shape = RoundedCornerShape(14.dp),
                contentPadding = PaddingValues(horizontal = 8.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (isLeftDown) XdeskOverlay.accent else XdeskOverlay.key,
                    contentColor = XdeskOverlay.content
                )
            ) {
                Text(
                    "Chuột Trái",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    softWrap = false,
                )
            }

            Button(
                onClick = { onClick(InputButton.RIGHT) },
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight(),
                shape = RoundedCornerShape(14.dp),
                contentPadding = PaddingValues(horizontal = 8.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (isRightDown) XdeskOverlay.accent else XdeskOverlay.key,
                    contentColor = XdeskOverlay.content
                )
            ) {
                Text(
                    "Chuột Phải",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    softWrap = false,
                )
            }
        }
    }
}

private fun eventDurationMs(startUptimeMs: Long): Long =
    (android.os.SystemClock.uptimeMillis() - startUptimeMs).coerceAtLeast(0L)

@Composable
private fun KeyboardTabContent(
    activeMods: Int,
    inputText: String,
    onInputTextChange: (String) -> Unit,
    onSendText: () -> Unit,
    onToggleMod: (Int) -> Unit,
    onKey: (Int, Int) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .imePadding()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        // Khung gõ text tiếng Việt gửi sang Mac
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
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
                )
            )

            Button(
                onClick = onSendText,
                enabled = inputText.isNotEmpty(),
                modifier = Modifier.heightIn(min = 48.dp),
                shape = RoundedCornerShape(10.dp),
                contentPadding = PaddingValues(horizontal = 14.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = XdeskOverlay.accent,
                    contentColor = XdeskOverlay.content,
                    disabledContainerColor = XdeskOverlay.key,
                    disabledContentColor = XdeskOverlay.contentDisabled,
                )
            ) {
                Text("Gửi", fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = 1, softWrap = false)
            }
        }

        // Phím bổ trợ Mac: Cmd, Option, Ctrl, Shift
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            ModButton("⌘ Cmd", (activeMods and InputModifiers.COMMAND) != 0, Modifier.weight(1f)) {
                onToggleMod(InputModifiers.COMMAND)
            }
            ModButton("⌥ Opt", (activeMods and InputModifiers.OPTION) != 0, Modifier.weight(1f)) {
                onToggleMod(InputModifiers.OPTION)
            }
            ModButton("⌃ Ctrl", (activeMods and InputModifiers.CONTROL) != 0, Modifier.weight(1f)) {
                onToggleMod(InputModifiers.CONTROL)
            }
            ModButton("⇧ Shift", (activeMods and InputModifiers.SHIFT) != 0, Modifier.weight(1f)) {
                onToggleMod(InputModifiers.SHIFT)
            }
        }

        // Phím điều hướng / soạn thảo chính
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            KeyCapButton("Esc", Modifier.weight(1f)) { onKey(0x29, 0) }
            KeyCapButton("Tab", Modifier.weight(1f)) { onKey(0x2B, 0) }
            KeyCapButton("Space", Modifier.weight(1.4f)) { onKey(0x2C, 0) }
            KeyCapButton("⌫ Del", Modifier.weight(1f)) { onKey(0x2A, 0) }
            KeyCapButton("↩ Enter", Modifier.weight(1.2f)) { onKey(0x28, 0) }
        }

        // Phím tắt nhanh ⌘C/⌘V/⌘A + cụm phím mũi tên (tách 2 hàng gọn gàng như iOS)
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            KeyCapButton("⌘ C", Modifier.weight(1f)) { onKey(0x06, InputModifiers.COMMAND) }
            KeyCapButton("⌘ V", Modifier.weight(1f)) { onKey(0x19, InputModifiers.COMMAND) }
            KeyCapButton("⌘ A", Modifier.weight(1f)) { onKey(0x04, InputModifiers.COMMAND) }
        }

        Column(
            modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            KeyCapButton("↑", Modifier.width(68.dp).heightIn(min = 46.dp)) { onKey(0x52, 0) }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                KeyCapButton("←", Modifier.width(68.dp).heightIn(min = 46.dp)) { onKey(0x50, 0) }
                KeyCapButton("↓", Modifier.width(68.dp).heightIn(min = 46.dp)) { onKey(0x51, 0) }
                KeyCapButton("→", Modifier.width(68.dp).heightIn(min = 46.dp)) { onKey(0x4F, 0) }
            }
        }
    }
}

@Composable
private fun NumpadMediaTabContent(
    onKey: (Int, Int) -> Unit,
    onMediaKey: (MediaKeyKind) -> Unit,
    onSendText: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(
            "TRÌNH CHIẾU SLIDE & MEDIA",
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            color = XdeskOverlay.contentMuted
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            MediaTileButton("Trình chiếu (F5)", XdeskIcons.Presentation, Modifier.weight(1f)) { onKey(0x3E, 0) }
            MediaTileButton("Thoát (Esc)", XdeskIcons.ExitSlide, Modifier.weight(1f)) { onKey(0x29, 0) }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            MediaTileButton("Slide trước", XdeskIcons.ChevronLeftCircle, Modifier.weight(1f)) { onKey(0x4B, 0) }
            MediaTileButton("Slide kế", XdeskIcons.ChevronRightCircle, Modifier.weight(1f)) { onKey(0x4E, 0) }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            MediaTileButton("Space", XdeskIcons.SpaceBar, Modifier.weight(1f)) { onKey(0x2C, 0) }
            MediaTileButton("Hoàn tác", XdeskIcons.Undo, Modifier.weight(1f)) { onKey(0x1D, InputModifiers.COMMAND) }
        }

        HorizontalDivider(color = XdeskOverlay.divider)

        Text(
            "ÂM LƯỢNG & PHÁT NHẠC",
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            color = XdeskOverlay.contentMuted,
        )
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MediaTileButton("Bài trước", XdeskIcons.SkipPrevious, Modifier.weight(1f)) { onMediaKey(MediaKeyKind.PREVIOUS) }
            MediaTileButton("Phát / Dừng", XdeskIcons.PlayPause, Modifier.weight(1f)) { onMediaKey(MediaKeyKind.PLAY_PAUSE) }
            MediaTileButton("Bài kế", XdeskIcons.SkipNext, Modifier.weight(1f)) { onMediaKey(MediaKeyKind.NEXT) }
        }
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MediaTileButton("Tắt tiếng", XdeskIcons.VolumeOff, Modifier.weight(1f)) { onMediaKey(MediaKeyKind.MUTE) }
            MediaTileButton("Giảm âm", XdeskIcons.VolumeDown, Modifier.weight(1f)) { onMediaKey(MediaKeyKind.VOLUME_DOWN) }
            MediaTileButton("Tăng âm", XdeskIcons.VolumeUp, Modifier.weight(1f)) { onMediaKey(MediaKeyKind.VOLUME_UP) }
        }

        Spacer(Modifier.height(4.dp))

        Text(
            "BÀN PHÍM SỐ NUMPAD",
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            color = XdeskOverlay.contentMuted
        )

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            KeyCapButton("7", Modifier.weight(1f)) { onSendText("7") }
            KeyCapButton("8", Modifier.weight(1f)) { onSendText("8") }
            KeyCapButton("9", Modifier.weight(1f)) { onSendText("9") }
            KeyCapButton("/", Modifier.weight(1f)) { onSendText("/") }
        }
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            KeyCapButton("4", Modifier.weight(1f)) { onSendText("4") }
            KeyCapButton("5", Modifier.weight(1f)) { onSendText("5") }
            KeyCapButton("6", Modifier.weight(1f)) { onSendText("6") }
            KeyCapButton("*", Modifier.weight(1f)) { onSendText("*") }
        }
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            KeyCapButton("1", Modifier.weight(1f)) { onSendText("1") }
            KeyCapButton("2", Modifier.weight(1f)) { onSendText("2") }
            KeyCapButton("3", Modifier.weight(1f)) { onSendText("3") }
            KeyCapButton("-", Modifier.weight(1f)) { onSendText("-") }
        }
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            KeyCapButton("0", Modifier.weight(1f)) { onSendText("0") }
            KeyCapButton(".", Modifier.weight(1f)) { onSendText(".") }
            KeyCapButton("=", Modifier.weight(1f)) { onSendText("=") }
            KeyCapButton("+", Modifier.weight(1f)) { onSendText("+") }
        }
    }
}

@Composable
private fun ModButton(
    title: String,
    isActive: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        modifier = modifier.heightIn(min = 44.dp),
        shape = RoundedCornerShape(10.dp),
        contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = if (isActive) XdeskOverlay.accent else XdeskOverlay.key,
            contentColor = XdeskOverlay.content
        )
    ) {
        Text(title, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1, softWrap = false)
    }
}

@Composable
private fun KeyCapButton(
    title: String,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        modifier = modifier.heightIn(min = 44.dp),
        shape = RoundedCornerShape(10.dp),
        contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = XdeskOverlay.key,
            contentColor = XdeskOverlay.content
        )
    ) {
        Text(title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, maxLines = 1, softWrap = false)
    }
}

@Composable
private fun MediaTileButton(
    label: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Button(
        onClick = onClick,
        modifier = modifier.heightIn(min = 54.dp),
        shape = RoundedCornerShape(10.dp),
        contentPadding = PaddingValues(horizontal = 6.dp, vertical = 6.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = XdeskOverlay.key,
            contentColor = XdeskOverlay.content,
        ),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Icon(imageVector = icon, contentDescription = null, modifier = Modifier.size(19.dp))
            Text(
                label,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
