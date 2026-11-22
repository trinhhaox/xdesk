package vn.xox.xdesk.wire

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class WindowControlMessageTest {
    private fun roundTrip(message: ControlMessage): ControlMessage =
        ControlMessageCodec.decode(ControlMessageCodec.encode(ControlEnvelope(9, message))).message

    @Test
    fun capabilityBitIs14() = assertEquals(0x4000L, Capabilities.WINDOW_CONTROL)

    @Test
    fun roundTripsAllWindowMessages() {
        val all = listOf(
            ControlMessage.WindowPick(10.5, 20.0),
            ControlMessage.WindowSelected(true, 3, "Safari", "Tiêu đề", WindowFrame(1.0, 2.0, 300.0, 200.0), true),
            ControlMessage.WindowSelected.failure("Không có cửa sổ ở đây"),
            ControlMessage.WindowAdjust.move(3, -4.0, 8.5),
            ControlMessage.WindowAdjust.resize(3, 640.0, 480.0),
        ) + WindowPreset.entries.map { ControlMessage.WindowAdjust.preset(3, it) }
        for (message in all) assertEquals(message, roundTrip(message))
    }

    @Test
    fun rejectsInvalidValues() {
        val bad = listOf(
            ControlMessage.WindowPick(Double.NaN, 0.0),
            ControlMessage.WindowAdjust(1, WindowAdjustOp.MOVE, dx = 1.0),
            ControlMessage.WindowAdjust.move(1, Double.POSITIVE_INFINITY, 0.0),
            ControlMessage.WindowAdjust.resize(1, 0.0, 10.0),
            ControlMessage.WindowAdjust(1, WindowAdjustOp.PRESET),
            ControlMessage.WindowSelected(true, frame = WindowFrame(0.0, 0.0, -1.0, 5.0)),
        )
        for (message in bad) {
            assertFailsWith<WireException> { ControlMessageCodec.encode(ControlEnvelope(1, message)) }
        }
    }
}
