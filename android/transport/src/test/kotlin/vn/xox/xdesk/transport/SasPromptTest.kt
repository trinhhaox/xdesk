package vn.xox.xdesk.transport

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SasPromptTest {
    @Test
    fun keepsTheFirstAnswer() {
        var mismatches = 0
        val prompt = SasPrompt("123 456") { mismatches++ }
        prompt.answer(true)
        prompt.answer(false)
        assertTrue(prompt.awaitDecision(5_000))
        assertEquals(0, mismatches)
    }

    @Test
    fun mismatchRunsTheAbortHookOnce() {
        var mismatches = 0
        val prompt = SasPrompt("123 456") { mismatches++ }
        prompt.answer(false)
        prompt.answer(false)
        assertFalse(prompt.awaitDecision(5_000))
        assertEquals(1, mismatches)
    }

    @Test
    fun abandonEndsTheWaitWithoutTheAbortHook() {
        var mismatches = 0
        val prompt = SasPrompt("123 456") { mismatches++ }
        prompt.abandon()
        assertFalse(prompt.isPending)
        assertFalse(prompt.awaitDecision(5_000))
        assertEquals(0, mismatches)
    }

    @Test
    fun noAnswerTimesOutAsMismatch() {
        val prompt = SasPrompt("000 000")
        assertFalse(prompt.awaitDecision(50))
        assertEquals(false, prompt.answered)
    }
}
