package vn.xox.xdesk.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import vn.xox.xdesk.app.KeyboardStyleStore
import vn.xox.xdesk.app.ViewerController
import vn.xox.xdesk.app.WorkMode
import vn.xox.xdesk.app.ui.theme.XdeskOverlay
import vn.xox.xdesk.transport.InputButton
import vn.xox.xdesk.transport.InputEvents

/**
 * Màn điều khiển toàn màn hình (Chuột / Bàn phím / Slide & Số): thanh trên một hàng + nội dung lấp đầy phần còn lại.
 * Bố cục ngang/dọc suy ra từ kích thước thật; tôn trọng safe area (tai thỏ, thanh điều hướng, IME).
 */
@Composable
fun RemoteTrackpadSheet(
    controller: ViewerController,
    activeMode: WorkMode,
    onSelectMode: (WorkMode) -> Unit,
    modifier: Modifier = Modifier,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val keyboardStore = remember { KeyboardStyleStore(context.applicationContext) }
    var cursorX by remember { mutableFloatStateOf(0.5f) }
    var cursorY by remember { mutableFloatStateOf(0.5f) }
    var activeMods by remember { mutableIntStateOf(0) }
    var inputText by remember { mutableStateOf("") }
    var isLeftDown by remember { mutableStateOf(false) }
    var isRightDown by remember { mutableStateOf(false) }

    fun sendPointerMove(newX: Float, newY: Float) {
        cursorX = newX.coerceIn(0.001f, 0.999f)
        cursorY = newY.coerceIn(0.001f, 0.999f)
        controller.sendInput(listOf(InputEvents.move(cursorX, cursorY, activeMods)))
    }

    fun pointerButton(button: Int, down: Boolean) = InputEvents.button(down = down, x = cursorX, y = cursorY, button = button, mods = activeMods)

    fun sendKey(usage: Int, extraMods: Int = 0) {
        val mods = activeMods or extraMods
        controller.sendInput(listOf(InputEvents.key(usage, true, mods), InputEvents.key(usage, false, mods)))
    }

    val trackpad = TrackpadActions(
        onMove = { dx, dy -> sendPointerMove(cursorX + dx, cursorY + dy) },
        onClick = { button -> controller.sendInput(listOf(pointerButton(button, true), pointerButton(button, false))) },
        onScroll = { dx, dy -> controller.sendInput(listOf(InputEvents.scroll(dx, dy, activeMods))) },
        onLeftDownChange = { down -> isLeftDown = down; controller.sendInput(listOf(pointerButton(InputButton.LEFT, down))) },
        onThreeFingerShortcut = { usage, mods -> sendKey(usage, mods) },
    )

    BoxWithConstraints(modifier.fillMaxSize().background(XdeskOverlay.panel).windowInsetsPadding(WindowInsets.safeDrawing)) {
        val landscape = maxWidth > maxHeight
        Column(Modifier.fillMaxSize()) {
            ControlTopBar(
                targetName = controller.progress.targetName,
                activeMode = activeMode,
                onSelectMode = onSelectMode,
                landscape = landscape,
                keyboardStyle = keyboardStore.style.takeIf { activeMode == WorkMode.KEYBOARD },
                onSelectKeyboardStyle = keyboardStore::select,
                onLock = controller::sendSystemLock,
                onDisconnect = onDismiss,
            )
            HorizontalDivider(color = XdeskOverlay.divider)
            val content = Modifier.weight(1f).fillMaxWidth()
            Column(content) {
                when (activeMode) {
                    WorkMode.TRACKPAD -> MouseTabContent(landscape, isLeftDown, isRightDown, trackpad)
                    WorkMode.KEYBOARD -> KeyboardTabContent(
                        style = keyboardStore.style,
                        controller = controller,
                        landscape = landscape,
                        trackpad = trackpad,
                        activeMods = activeMods,
                        inputText = inputText,
                        onInputTextChange = { inputText = it },
                        onSendText = { if (inputText.isNotEmpty()) controller.sendText(inputText); inputText = "" },
                        onToggleMod = { bit -> activeMods = activeMods xor bit },
                        onKey = { usage, mods -> sendKey(usage, mods) },
                    )
                    WorkMode.NUMPAD_MEDIA -> SlideNumpadContent(
                        SlideNumpadActions(onKey = { usage, mods -> sendKey(usage, mods) }, onMediaKey = controller::sendMediaKey),
                        landscape,
                    )
                    WorkMode.MIRROR, WorkMode.EXTEND -> Unit
                }
            }
        }
    }
}
