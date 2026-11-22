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
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.TabRowDefaults
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
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
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.hypot
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.ui.theme.XdeskOverlay
import vn.xox.xdesk.transport.InputButton
import vn.xox.xdesk.transport.InputEvents
import vn.xox.xdesk.transport.InputModifiers

enum class RemoteTab(val title: String) {
    TRACKPAD("Trackpad"),
    KEYBOARD("Bàn phím"),
    NUMPAD_MEDIA("Số & Media")
}

@Composable
fun RemoteTrackpadSheet(
    controller: ViewerController,
    isFullscreen: Boolean = false,
    onSwitchToScreen: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
    onDismiss: () -> Unit
) {
    var selectedTab by remember { mutableStateOf(RemoteTab.TRACKPAD) }
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
        // Tier 1: Nút Màn hình + Tên máy Mac + Khoá / Ngắt kết nối
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (isFullscreen && onSwitchToScreen != null) {
                Surface(
                    onClick = onSwitchToScreen,
                    shape = CircleShape,
                    color = XdeskOverlay.key,
                    modifier = Modifier.heightIn(min = 44.dp),
                ) {
                    Row(
                        Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Icon(XdeskIcons.Monitor, contentDescription = null, Modifier.size(18.dp), tint = XdeskOverlay.accentLight)
                        Text("Màn hình", color = XdeskOverlay.accentLight, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, softWrap = false)
                    }
                }
            } else {
                IconButton(onClick = onDismiss) {
                    Icon(
                        imageVector = if (isFullscreen) XdeskIcons.Stop else XdeskIcons.Chevron,
                        contentDescription = if (isFullscreen) "Ngắt kết nối" else "Đóng",
                        tint = if (isFullscreen) XdeskOverlay.danger else XdeskOverlay.content,
                    )
                }
            }

            Text(
                controller.progress.targetName.ifBlank { "Điều khiển Mac" },
                modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
                color = XdeskOverlay.content,
                fontSize = 15.sp,
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
                if (isFullscreen) {
                    IconButton(onClick = onDismiss) {
                        Icon(
                            imageVector = XdeskIcons.Stop,
                            contentDescription = "Ngắt kết nối",
                            tint = XdeskOverlay.danger,
                        )
                    }
                }
            }
        }

        // Tier 2: Thanh 3 tab rộng hết bề ngang, không rớt dòng
        TabRow(
            selectedTabIndex = selectedTab.ordinal,
            containerColor = Color.Transparent,
            contentColor = XdeskOverlay.content,
            divider = { androidx.compose.material3.HorizontalDivider(color = XdeskOverlay.divider) },
            indicator = { tabPositions ->
                TabRowDefaults.SecondaryIndicator(
                    Modifier.tabIndicatorOffset(tabPositions[selectedTab.ordinal]),
                    color = XdeskOverlay.accentLight,
                )
            },
            modifier = Modifier.fillMaxWidth(),
        ) {
            RemoteTab.entries.forEach { tab ->
                Tab(
                    selected = selectedTab == tab,
                    onClick = { selectedTab = tab },
                    text = {
                        Text(
                            tab.title,
                            fontSize = 13.sp,
                            fontWeight = if (selectedTab == tab) FontWeight.Bold else FontWeight.Medium,
                            color = if (selectedTab == tab) XdeskOverlay.content else XdeskOverlay.contentMuted,
                            maxLines = 1,
                            softWrap = false,
                        )
                    }
                )
            }
        }

        Spacer(Modifier.height(10.dp))

        when (selectedTab) {
            RemoteTab.TRACKPAD -> {
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
                    }
                )
            }
            RemoteTab.KEYBOARD -> {
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
            RemoteTab.NUMPAD_MEDIA -> {
                NumpadMediaTabContent(
                    onKey = { usage -> sendKey(usage) },
                    onSendText = { char -> sendTextDirect(char) }
                )
            }
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
    onRightDownChange: (Boolean) -> Unit
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
        // Vùng cảm ứng Trackpad (1 ngón di/chạm trái, 2 ngón chạm phải / vuốt cuộn trang)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .clip(RoundedCornerShape(16.dp))
                .background(XdeskOverlay.bar)
                .border(1.dp, XdeskOverlay.divider, RoundedCornerShape(16.dp))
                .pointerInput(Unit) {
                    val slopPx = viewConfiguration.touchSlop
                    awaitEachGesture {
                        val firstDown = awaitFirstDown(requireUnconsumed = false)
                        val startTime = firstDown.uptimeMillis
                        var maxPointers = 1
                        var totalMoved = 0f
                        var movedBeyondSlop = false
                        var previousPositions = mapOf(firstDown.id to firstDown.position)

                        while (true) {
                            val event = awaitPointerEvent()
                            val pressed = event.changes.filter { it.pressed }
                            maxPointers = maxOf(maxPointers, pressed.size, event.changes.size)
                            if (pressed.isEmpty()) break

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
                                    if (pressed.size >= 2 || maxPointers >= 2) {
                                        val dpScale = 1.4f / density
                                        onScroll(avgDx * dpScale, avgDy * dpScale)
                                    } else {
                                        val sensitivity = 0.0018f
                                        onMove(avgDx * sensitivity, avgDy * sensitivity)
                                    }
                                }
                            }
                            previousPositions = pressed.associate { it.id to it.position }
                        }

                        if (!movedBeyondSlop) {
                            val duration = (eventDurationMs(startTime))
                            if (maxPointers >= 2 && duration <= 350L) {
                                onClick(InputButton.RIGHT)
                            } else if (maxPointers == 1 && duration <= 300L) {
                                onClick(InputButton.LEFT)
                            }
                        }
                    }
                },
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(horizontal = 16.dp)) {
                Icon(
                    imageVector = XdeskIcons.Cursor,
                    contentDescription = null,
                    tint = XdeskOverlay.contentMuted.copy(alpha = 0.5f),
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
                    "1 ngón: Di chuột · Chạm: Chuột trái\n2 ngón chạm: Chuột phải · 2 ngón vuốt: Cuộn trang",
                    color = XdeskOverlay.contentMuted.copy(alpha = 0.7f),
                    fontSize = 11.sp,
                    textAlign = TextAlign.Center,
                    lineHeight = 16.sp,
                )
            }
        }

        // Hai nút chuột vật lý dưới đáy (fillMaxHeight thay vì fillMaxSize trong Row)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(58.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Button(
                onClick = { onClick(InputButton.LEFT) },
                modifier = Modifier
                    .weight(1.5f)
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
                modifier = Modifier.heightIn(min = 48.dp),
                shape = RoundedCornerShape(10.dp),
                contentPadding = PaddingValues(horizontal = 14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = XdeskOverlay.accent, contentColor = XdeskOverlay.content)
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
            KeyCapButton("⏎ Enter", Modifier.weight(1.2f)) { onKey(0x28, 0) }
        }

        // Phím tắt nhanh ⌘C/⌘V/⌘A + cụm phím mũi tên
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            KeyCapButton("⌘ C", Modifier.weight(1f)) { onKey(0x06, InputModifiers.COMMAND) }
            KeyCapButton("⌘ V", Modifier.weight(1f)) { onKey(0x19, InputModifiers.COMMAND) }
            KeyCapButton("⌘ A", Modifier.weight(1f)) { onKey(0x04, InputModifiers.COMMAND) }

            Spacer(Modifier.width(4.dp))

            KeyCapButton("←", Modifier.weight(0.9f)) { onKey(0x50, 0) }
            Column(Modifier.weight(0.9f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                KeyCapButton("↑", Modifier.fillMaxWidth()) { onKey(0x52, 0) }
                KeyCapButton("↓", Modifier.fillMaxWidth()) { onKey(0x51, 0) }
            }
            KeyCapButton("→", Modifier.weight(0.9f)) { onKey(0x4F, 0) }
        }
    }
}

@Composable
private fun NumpadMediaTabContent(
    onKey: (Int) -> Unit,
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
            "ĐIỀU KHIỂN TRÌNH CHIẾU SLIDE",
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            color = XdeskOverlay.contentMuted
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            KeyCapButton("▶ F5", Modifier.weight(1f)) { onKey(0x3E) }
            KeyCapButton("Esc", Modifier.weight(1f)) { onKey(0x29) }
            KeyCapButton("◀ Trước", Modifier.weight(1.2f)) { onKey(0x4B) }
            KeyCapButton("Sau ▶", Modifier.weight(1.2f)) { onKey(0x4E) }
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
