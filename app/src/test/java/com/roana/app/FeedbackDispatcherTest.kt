package com.roana.app

import com.roana.app.CorridorPlanner.CorridorCommand
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FeedbackDispatcherTest {
    @Test
    fun changedRightCommandSpeaksTurnRight() {
        val spoken = mutableListOf<SpokenFeedback>()
        val dispatcher = dispatcher(spoken)

        val event = dispatcher.dispatch(
            state(
                command = CorridorCommand.RIGHT,
                sourceCommand = CorridorCommand.RIGHT,
                changed = true,
            ),
        )

        assertTrue(event.spoken)
        assertEquals(CorridorCommand.RIGHT, event.command)
        assertEquals("turn_right", event.messageKey)
        assertEquals("utterance-1", event.utteranceId)
        assertEquals(
            listOf(SpokenFeedback("Turn right", FeedbackDispatcher.QueueMode.FLUSH, "utterance-1")),
            spoken,
        )
    }

    @Test
    fun unchangedPendingNonStopDoesNotSpeakInitialStop() {
        val spoken = mutableListOf<SpokenFeedback>()
        val dispatcher = dispatcher(spoken)

        val event = dispatcher.dispatch(
            CorridorStateMachine.CorridorState(
                command = CorridorCommand.STOP,
                sourceDecision = decision(CorridorCommand.STRAIGHT, reason = "path_found"),
                pendingCommand = CorridorCommand.STRAIGHT,
                pendingCount = 1,
                changed = false,
            ),
        )

        assertFalse(event.spoken)
        assertNull(event.utteranceId)
        assertTrue(spoken.isEmpty())
    }

    @Test
    fun initialEmergencyStopSpeaksOnce() {
        val spoken = mutableListOf<SpokenFeedback>()
        val dispatcher = dispatcher(spoken)

        val first = dispatcher.dispatch(
            state(
                command = CorridorCommand.STOP,
                sourceCommand = CorridorCommand.STOP,
                reason = "near_obstacle",
                changed = false,
            ),
        )
        val second = dispatcher.dispatch(
            state(
                command = CorridorCommand.STOP,
                sourceCommand = CorridorCommand.STOP,
                reason = "near_obstacle",
                changed = false,
            ),
        )

        assertTrue(first.spoken)
        assertFalse(second.spoken)
        assertEquals(listOf(SpokenFeedback("Stop", FeedbackDispatcher.QueueMode.FLUSH, "utterance-1")), spoken)
    }

    @Test
    fun debugForceSpeaksUnchangedState() {
        val spoken = mutableListOf<SpokenFeedback>()
        val dispatcher = dispatcher(spoken)

        val event = dispatcher.dispatch(
            state(
                command = CorridorCommand.STRAIGHT,
                sourceCommand = CorridorCommand.STRAIGHT,
                changed = false,
            ),
            force = true,
        )

        assertTrue(event.spoken)
        assertEquals("go_straight", event.messageKey)
        assertEquals(listOf(SpokenFeedback("Go straight", FeedbackDispatcher.QueueMode.FLUSH, "utterance-1")), spoken)
    }

    private fun dispatcher(spoken: MutableList<SpokenFeedback>): FeedbackDispatcher {
        var nextUtterance = 1
        return FeedbackDispatcher(
            speaker = FeedbackDispatcher.Speaker { message, queueMode, utteranceId ->
                spoken += SpokenFeedback(message, queueMode, utteranceId)
            },
            utteranceIdFactory = { "utterance-${nextUtterance++}" },
        )
    }

    private fun state(
        command: CorridorCommand,
        sourceCommand: CorridorCommand,
        reason: String = "path_found",
        changed: Boolean,
    ): CorridorStateMachine.CorridorState =
        CorridorStateMachine.CorridorState(
            command = command,
            sourceDecision = decision(sourceCommand, reason),
            pendingCommand = null,
            pendingCount = 0,
            changed = changed,
        )

    private fun decision(
        command: CorridorCommand,
        reason: String,
    ): CorridorPlanner.CorridorDecision =
        CorridorPlanner.CorridorDecision(command = command, path = emptyList(), reason = reason)

    private data class SpokenFeedback(
        val message: String,
        val queueMode: FeedbackDispatcher.QueueMode,
        val utteranceId: String,
    )
}
