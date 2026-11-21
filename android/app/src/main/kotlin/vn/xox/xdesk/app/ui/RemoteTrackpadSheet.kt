package vn.xox.xdesk.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.ViewerController
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

    fun sendKey(usage: Int) {
        controller.sendInput(listOf(
            InputEvents.key(usage, true, activeMods),
            InputEvents.key(usage, false, activeMods)
        ))
    }

    fun sendTextDirect(text: String) {
        if (text.isNotEmpty()) {
            controller.sendText(text)
        }
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(Color(0xFF141416))
            .padding(top = 8.dp, bottom = 16.dp)
    ) {
        // Top Bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onDismiss) {
                Icon(
                    imageVector = XdeskIcons.Chevron,
                    contentDescription = "Đóng",
                    tint = Color.White.copy(alpha = 0.8f)
                )
            }

            Spacer(Modifier.weight(1f))

            TabRow(
                selectedTabIndex = selectedTab.ordinal,
                containerColor = Color.Transparent,
                contentColor = Color.White,
                indicator = { tabPositions ->
                    TabRowDefaults.SecondaryIndicator(
                        Modifier.tabIndicatorOffset(tabPositions[selectedTab.ordinal]),
                        color = Color(0xFF3B82F6)
                    )
                },
                modifier = Modifier.width(280.dp)
            ) {
                RemoteTab.values().forEach { tab ->
                    Tab(
                        selected = selectedTab == tab,
                        onClick = { selectedTab = tab },
                        text = {
                            Text(
                                tab.title,
                                fontSize = 13.sp,
                                fontWeight = if (selectedTab == tab) FontWeight.Bold else FontWeight.Normal,
                                color = if (selectedTab == tab) Color.White else Color.White.copy(alpha = 0.6f)
                            )
                        }
                    )
                }
            }

            Spacer(Modifier.weight(1f))

            IconButton(onClick = { controller.sendSystemLock() }) {
                Icon(
                    imageVector = XdeskIcons.Lock,
                    contentDescription = "Khóa Mac",
                    tint = Color.White.copy(alpha = 0.8f)
                )
            }
        }

        Spacer(Modifier.height(8.dp))

        // Content
        when (selectedTab) {
            RemoteTab.TRACKPAD -> {
                TrackpadTabContent(
                    cursorX = cursorX,
                    cursorY = cursorY,
                    isLeftDown = isLeftDown,
                    isRightDown = isRightDown,
                    onMove = { dx, dy ->
                        sendPointerMove(cursorX + dx, cursorY + dy)
                    },
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
                    onKey = { usage -> sendKey(usage) }
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
private fun TrackpadTabContent(
    cursorX: Float,
    cursorY: Float,
    isLeftDown: Boolean,
    isRightDown: Boolean,
    onMove: (Float, Float) -> Unit,
    onClick: (Int) -> Unit,
    onScroll: (Float, Float) -> Unit,
    onLeftDownChange: (Boolean) -> Unit,
    onRightDownChange: (Boolean) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .height(340.dp)
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        // Trackpad Touch Surface
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .clip(RoundedCornerShape(16.dp))
                .background(Color(0xFF1E1E22))
                .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(16.dp))
                .pointerInput(Unit) {
                    detectTapGestures(
                        onTap = { onClick(InputButton.LEFT) },
                        onDoubleTap = {
                            onClick(InputButton.LEFT)
                            onClick(InputButton.LEFT)
                        },
                        onLongPress = { onClick(InputButton.RIGHT) }
                    )
                }
                .pointerInput(Unit) {
                    detectDragGestures { change, dragAmount ->
                        change.consume()
                        val sensitivity = 0.0018f
                        onMove(dragAmount.x * sensitivity, dragAmount.y * sensitivity)
                    }
                },
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    imageVector = XdeskIcons.Cursor,
                    contentDescription = null,
                    tint = Color.White.copy(alpha = 0.2f),
                    modifier = Modifier.size(36.dp)
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    "Bàn di chuột cảm ứng",
                    color = Color.White.copy(alpha = 0.35f),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium
                )
                Text(
                    "1 ngón: Di chuột / Chạm chuột trái • Nhấn giữ: Chuột phải",
                    color = Color.White.copy(alpha = 0.25f),
                    fontSize = 11.sp
                )
            }
        }

        // Physical Mouse Buttons (Left / Right)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(64.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Left Button
            Button(
                onClick = { onClick(InputButton.LEFT) },
                modifier = Modifier
                    .weight(1.5f)
                    .fillMaxSize(),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (isLeftDown) Color(0xFF2563EB) else Color(0xFF282830),
                    contentColor = Color.White
                )
            ) {
                Text(
                    "Chuột Trái",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            // Right Button
            Button(
                onClick = { onClick(InputButton.RIGHT) },
                modifier = Modifier
                    .weight(1f)
                    .fillMaxSize(),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (isRightDown) Color(0xFF2563EB) else Color(0xFF282830),
                    contentColor = Color.White
                )
            ) {
                Text(
                    "Chuột Phải",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}

@Composable
private fun KeyboardTabContent(
    activeMods: Int,
    inputText: String,
    onInputTextChange: (String) -> Unit,
    onSendText: () -> Unit,
    onToggleMod: (Int) -> Unit,
    onKey: (Int) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        // Direct Text Input with accents
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedTextField(
                value = inputText,
                onValueChange = onInputTextChange,
                modifier = Modifier.weight(1f),
                placeholder = { Text("Nhập tiếng Việt / văn bản sang Mac…", fontSize = 13.sp, color = Color.Gray) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                keyboardActions = KeyboardActions(onSend = { onSendText() }),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Color(0xFF3B82F6),
                    unfocusedBorderColor = Color.White.copy(alpha = 0.2f),
                    focusedTextColor = Color.White,
                    unfocusedTextColor = Color.White,
                    cursorColor = Color(0xFF3B82F6)
                )
            )

            Button(
                onClick = onSendText,
                shape = RoundedCornerShape(10.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF2563EB))
            ) {
                Text("Gửi", fontSize = 13.sp, fontWeight = FontWeight.Bold)
            }
        }

        // Mac Modifier Keys: Cmd, Option, Ctrl, Shift
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            ModButton("⌘ Cmd", (activeMods and InputModifiers.COMMAND) != 0, Modifier.weight(1f)) {
                onToggleMod(InputModifiers.COMMAND)
            }
            ModButton("⌥ Option", (activeMods and InputModifiers.OPTION) != 0, Modifier.weight(1f)) {
                onToggleMod(InputModifiers.OPTION)
            }
            ModButton("⌃ Control", (activeMods and InputModifiers.CONTROL) != 0, Modifier.weight(1f)) {
                onToggleMod(InputModifiers.CONTROL)
            }
            ModButton("⇧ Shift", (activeMods and InputModifiers.SHIFT) != 0, Modifier.weight(1f)) {
                onToggleMod(InputModifiers.SHIFT)
            }
        }

        // Essential Navigation / Edit Keys: Esc, Tab, Space, Delete, Enter
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            KeyCapButton("Esc", Modifier.weight(1f)) { onKey(0x29) }
            KeyCapButton("Tab", Modifier.weight(1f)) { onKey(0x2B) }
            KeyCapButton("Space", Modifier.weight(1.5f)) { onKey(0x2C) }
            KeyCapButton("⌫ Del", Modifier.weight(1f)) { onKey(0x2A) }
            KeyCapButton("⏎ Return", Modifier.weight(1.3f)) { onKey(0x28) }
        }

        // Arrow Keys & Common Shortcuts
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            KeyCapButton("⌘ C", Modifier.weight(1f)) {
                onToggleMod(InputModifiers.COMMAND)
                onKey(0x06) // c
                onToggleMod(InputModifiers.COMMAND)
            }
            KeyCapButton("⌘ V", Modifier.weight(1f)) {
                onToggleMod(InputModifiers.COMMAND)
                onKey(0x19) // v
                onToggleMod(InputModifiers.COMMAND)
            }
            KeyCapButton("⌘ A", Modifier.weight(1f)) {
                onToggleMod(InputModifiers.COMMAND)
                onKey(0x04) // a
                onToggleMod(InputModifiers.COMMAND)
            }

            Spacer(Modifier.width(8.dp))

            // Directional Pad
            KeyCapButton("←", Modifier.weight(0.9f)) { onKey(0x50) }
            Column(Modifier.weight(0.9f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                KeyCapButton("↑", Modifier.fillMaxWidth()) { onKey(0x52) }
                KeyCapButton("↓", Modifier.fillMaxWidth()) { onKey(0x51) }
            }
            KeyCapButton("→", Modifier.weight(0.9f)) { onKey(0x4F) }
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
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        // Slide / Presentation Remote Controls
        Text(
            "ĐIỀU KHIỂN TRÌNH CHIẾU SLIDE",
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White.copy(alpha = 0.5f)
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            KeyCapButton("▶ Chiếu F5", Modifier.weight(1f)) { onKey(0x3E) } // F5
            KeyCapButton("Thoát Esc", Modifier.weight(1f)) { onKey(0x29) } // Esc
            KeyCapButton("◀ Slide Trước", Modifier.weight(1.3f)) { onKey(0x4B) } // PageUp
            KeyCapButton("Slide Sau ▶", Modifier.weight(1.3f)) { onKey(0x4E) } // PageDown
        }

        Spacer(Modifier.height(4.dp))

        // Numpad 4x4 Grid
        Text(
            "BÀN PHÍM SỐ NUMPAD",
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White.copy(alpha = 0.5f)
        )

        // Row 1: 7 8 9 /
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            KeyCapButton("7", Modifier.weight(1f)) { onSendText("7") }
            KeyCapButton("8", Modifier.weight(1f)) { onSendText("8") }
            KeyCapButton("9", Modifier.weight(1f)) { onSendText("9") }
            KeyCapButton("/", Modifier.weight(1f)) { onSendText("/") }
        }
        // Row 2: 4 5 6 *
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            KeyCapButton("4", Modifier.weight(1f)) { onSendText("4") }
            KeyCapButton("5", Modifier.weight(1f)) { onSendText("5") }
            KeyCapButton("6", Modifier.weight(1f)) { onSendText("6") }
            KeyCapButton("*", Modifier.weight(1f)) { onSendText("*") }
        }
        // Row 3: 1 2 3 -
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            KeyCapButton("1", Modifier.weight(1f)) { onSendText("1") }
            KeyCapButton("2", Modifier.weight(1f)) { onSendText("2") }
            KeyCapButton("3", Modifier.weight(1f)) { onSendText("3") }
            KeyCapButton("-", Modifier.weight(1f)) { onSendText("-") }
        }
        // Row 4: 0 . = +
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
        modifier = modifier.height(42.dp),
        shape = RoundedCornerShape(10.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = if (isActive) Color(0xFF2563EB) else Color(0xFF24242A),
            contentColor = Color.White
        )
    ) {
        Text(title, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1)
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
        modifier = modifier.height(42.dp),
        shape = RoundedCornerShape(10.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = Color(0xFF2C2C34),
            contentColor = Color.White
        )
    ) {
        Text(title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
    }
}
