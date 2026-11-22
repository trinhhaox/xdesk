package vn.xox.xdesk.app

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import vn.xox.xdesk.app.input.KeyRepeater
import vn.xox.xdesk.app.input.MacKeyLayout.CAPS_LOCK
import vn.xox.xdesk.app.input.MacKeyLayout.LEFT_COMMAND
import vn.xox.xdesk.app.input.MacKeyLayout.LEFT_SHIFT
import vn.xox.xdesk.app.input.MacKeyLayout.RIGHT_SHIFT
import vn.xox.xdesk.app.input.CapsLockState
import vn.xox.xdesk.app.input.MacKeyboardEngine
import vn.xox.xdesk.app.input.MacKeyboardEngine.ModState
import vn.xox.xdesk.transport.InputModifiers
import vn.xox.xdesk.wire.InputEvent

class MacKeyboardEngineTest {
    private val keyC = 0x06
    private val keyA = 0x04
    private val engine = MacKeyboardEngine()

    /** (usage, down, mods) của từng sự kiện để so sánh gọn. */
    private fun List<InputEvent>.t() = map { Triple(it.keyUsage, it.button == 1, it.mods) }

    @Test
    fun plainKeySendsRealDownThenUpOnRelease() {
        assertEquals(listOf(Triple(keyA, true, 0)), engine.keyDown(keyA, 0).t())
        assertTrue(keyA in engine.snapshot().pressed)
        assertEquals(listOf(Triple(keyA, false, 0)), engine.keyUp(keyA).t())
        assertTrue(engine.snapshot().pressed.isEmpty())
    }

    @Test
    fun oneShotModifierAppliesToNextKeyThenReleases() {
        assertEquals(listOf(Triple(LEFT_SHIFT, true, InputModifiers.SHIFT)), engine.modifierDown(LEFT_SHIFT, 0).t())
        assertEquals(emptyList(), engine.modifierUp(LEFT_SHIFT, 100))
        assertEquals(ModState.ARMED, engine.snapshot().modState(LEFT_SHIFT))
        assertEquals(listOf(Triple(keyA, true, InputModifiers.SHIFT)), engine.keyDown(keyA, 200).t())
        assertEquals(
            listOf(Triple(keyA, false, InputModifiers.SHIFT), Triple(LEFT_SHIFT, false, 0)),
            engine.keyUp(keyA).t(),
        )
        assertEquals(0, engine.activeMods)
    }

    @Test
    fun slowSecondTapKeepsArmedAndQuickLiftCancels() {
        engine.modifierDown(LEFT_SHIFT, 0); engine.modifierUp(LEFT_SHIFT, 50)
        assertEquals(emptyList(), engine.modifierDown(LEFT_SHIFT, 1000))
        assertEquals(ModState.ARMED, engine.snapshot().modState(LEFT_SHIFT))
        assertEquals(listOf(Triple(LEFT_SHIFT, false, 0)), engine.modifierUp(LEFT_SHIFT, 1100).t())
        assertEquals(ModState.OFF, engine.snapshot().modState(LEFT_SHIFT))
    }

    @Test
    fun slowSecondTapWithChordReleasesNormallyAndRestartsDoubleTapWindow() {
        engine.modifierDown(LEFT_SHIFT, 0); engine.modifierUp(LEFT_SHIFT, 50)
        engine.modifierDown(LEFT_SHIFT, 1000)
        assertEquals(listOf(Triple(keyA, true, InputModifiers.SHIFT)), engine.keyDown(keyA, 1010).t())
        engine.keyUp(keyA)
        assertEquals(listOf(Triple(LEFT_SHIFT, false, 0)), engine.modifierUp(LEFT_SHIFT, 1100).t())
        engine.modifierDown(LEFT_COMMAND, 2000); engine.modifierUp(LEFT_COMMAND, 2050)
        engine.modifierDown(LEFT_COMMAND, 2500)
        assertEquals(ModState.ARMED, engine.snapshot().modState(LEFT_COMMAND))
        engine.modifierDown(LEFT_COMMAND, 2800)
        assertEquals(ModState.LOCKED, engine.snapshot().modState(LEFT_COMMAND))
    }

    @Test
    fun oneShotModifierIsConsumedAtKeyDownSoOverlappingKeysTypeHi() {
        engine.modifierDown(LEFT_SHIFT, 0); engine.modifierUp(LEFT_SHIFT, 50)
        val h = 0x0B
        val i = 0x0C
        assertEquals(listOf(Triple(h, true, InputModifiers.SHIFT)), engine.keyDown(h, 100).t())
        assertEquals(ModState.OFF, engine.snapshot().modState(LEFT_SHIFT))
        assertEquals(listOf(Triple(i, true, 0)), engine.keyDown(i, 150).t())
        assertEquals(listOf(Triple(h, false, InputModifiers.SHIFT), Triple(LEFT_SHIFT, false, 0)), engine.keyUp(h).t())
        assertEquals(listOf(Triple(i, false, 0)), engine.keyUp(i).t())
    }

    @Test
    fun doubleTapLocksUntilTappedAgain() {
        engine.modifierDown(LEFT_COMMAND, 0); engine.modifierUp(LEFT_COMMAND, 50)
        assertEquals(emptyList(), engine.modifierDown(LEFT_COMMAND, 400))
        engine.modifierUp(LEFT_COMMAND, 450)
        assertEquals(ModState.LOCKED, engine.snapshot().modState(LEFT_COMMAND))
        engine.keyDown(keyC, 500); engine.keyUp(keyC)
        assertEquals(InputModifiers.COMMAND, engine.activeMods)
        assertEquals(listOf(Triple(LEFT_COMMAND, false, 0)), engine.modifierDown(LEFT_COMMAND, 5000).t())
        assertEquals(0, engine.activeMods)
    }

    @Test
    fun holdWithChordReleasesOnFingerUp() {
        engine.modifierDown(LEFT_COMMAND, 0)
        assertEquals(listOf(Triple(keyC, true, InputModifiers.COMMAND)), engine.keyDown(keyC, 10).t())
        assertEquals(listOf(Triple(keyC, false, InputModifiers.COMMAND)), engine.keyUp(keyC).t())
        assertEquals(InputModifiers.COMMAND, engine.activeMods)
        assertEquals(listOf(Triple(LEFT_COMMAND, false, 0)), engine.modifierUp(LEFT_COMMAND, 100).t())
        assertEquals(0, engine.activeMods)
    }

    @Test
    fun longHoldWithoutChordReleasesOnLiftButQuickTapStaysArmed() {
        engine.modifierDown(LEFT_SHIFT, 0)
        assertEquals(listOf(Triple(LEFT_SHIFT, false, 0)), engine.modifierUp(LEFT_SHIFT, 351).t())
        engine.modifierDown(LEFT_SHIFT, 1000)
        assertEquals(emptyList(), engine.modifierUp(LEFT_SHIFT, 1350))
        assertEquals(ModState.ARMED, engine.snapshot().modState(LEFT_SHIFT))
    }

    @Test
    fun combinesMultipleModifiers() {
        engine.modifierDown(LEFT_COMMAND, 0)
        engine.modifierDown(LEFT_SHIFT, 0)
        assertEquals(InputModifiers.COMMAND or InputModifiers.SHIFT, engine.keyDown(0x14, 0).single().mods)
    }

    @Test
    fun capsLockLivesOnPhoneSetsModBitAndSendsNoHid() {
        assertEquals(emptyList(), engine.keyDown(CAPS_LOCK, 0))
        assertEquals(emptyList(), engine.keyUp(CAPS_LOCK))
        assertTrue(engine.snapshot().capsLock)
        assertEquals(Triple(keyA, true, InputModifiers.CAPS_LOCK), engine.keyDown(keyA, 10).t().single())
        engine.keyUp(keyA)
        engine.keyDown(CAPS_LOCK, 100); engine.keyUp(CAPS_LOCK)
        assertEquals(false, engine.snapshot().capsLock)
        assertEquals(Triple(keyA, true, 0), engine.keyDown(keyA, 200).t().single())
    }

    @Test
    fun capsLockSurvivesRebuiltEngineWithSharedState() {
        val caps = CapsLockState()
        MacKeyboardEngine(caps).apply { keyDown(CAPS_LOCK, 0); keyUp(CAPS_LOCK) }
        assertTrue(MacKeyboardEngine(caps).snapshot().capsLock)
        assertEquals(InputModifiers.CAPS_LOCK, MacKeyboardEngine(caps).activeMods)
    }

    @Test
    fun shiftActiveReflectsEitherShiftKey() {
        assertEquals(false, engine.snapshot().shiftActive)
        engine.modifierDown(RIGHT_SHIFT, 0)
        assertTrue(engine.snapshot().shiftActive)
    }

    @Test
    fun releaseAllFreesHeldKeysAndModifiersWithoutStuckState() {
        engine.modifierDown(LEFT_COMMAND, 0); engine.modifierUp(LEFT_COMMAND, 0)
        engine.modifierDown(LEFT_SHIFT, 0)
        engine.keyDown(keyA, 0)
        val events = engine.releaseAll()
        assertTrue(events.all { it.button == 0 })
        assertEquals(setOf(keyA, LEFT_COMMAND, LEFT_SHIFT), events.map { it.keyUsage }.toSet())
        assertEquals(0, events.last().mods)
        assertEquals(0, engine.activeMods)
        assertTrue(engine.snapshot().pressed.isEmpty())
        assertEquals(emptyList(), engine.tick(10_000))
        assertEquals(emptyList(), engine.releaseAll())
    }

    @Test
    fun repeatStartsAfterDelayAndStopsOnRelease() {
        engine.keyDown(keyA, 1000)
        assertEquals(emptyList(), engine.tick(1399))
        assertEquals(listOf(Triple(keyA, true, 0)), engine.tick(1400).t())
        assertEquals(emptyList(), engine.tick(1420))
        assertEquals(1, engine.tick(1433).size)
        engine.keyUp(keyA)
        assertEquals(emptyList(), engine.tick(5000))
    }

    @Test
    fun repeatCarriesModifiersAndSkipsModifierKeysAndCapsLock() {
        engine.modifierDown(LEFT_SHIFT, 0)
        engine.keyDown(keyA, 0)
        assertEquals(InputModifiers.SHIFT, engine.tick(400).single().mods)
        engine.keyUp(keyA)
        engine.keyDown(CAPS_LOCK, 0)
        assertEquals(emptyList(), engine.tick(2000))
    }

    @Test
    fun repeaterCapsBurstAfterLongStall() {
        val r = KeyRepeater()
        r.keyDown(keyA, 0, 0)
        assertEquals(KeyRepeater.MAX_BURST.toInt(), r.tick(10_000).size)
    }

    @Test
    fun onlyLatestKeyRepeats() {
        engine.keyDown(keyA, 0)
        engine.keyDown(keyC, 100)
        assertEquals(keyC, engine.tick(500).single().keyUsage)
        engine.keyUp(keyA)
        assertTrue(engine.tick(600).isNotEmpty())
    }
}
