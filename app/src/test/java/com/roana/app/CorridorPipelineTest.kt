package com.roana.app

import com.roana.app.CorridorPlanner.CorridorCommand
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CorridorPipelineTest {
    @Test
    fun keepsNonStopCommandPendingUntilConfirmed() {
        val pipeline = CorridorPipeline(stateMachine = CorridorStateMachine(confirmationsRequired = 3))
        val grid = corridorGrid()

        assertEquals(CorridorCommand.STOP, pipeline.process(grid).state.command)
        assertEquals(CorridorCommand.STOP, pipeline.process(grid).state.command)
        val third = pipeline.process(grid)

        assertEquals(CorridorCommand.STRAIGHT, third.decision.command)
        assertEquals(CorridorCommand.STRAIGHT, third.state.command)
        assertTrue(third.state.changed)
    }

    @Test
    fun dispatchesFeedbackWhenDispatcherIsPresent() {
        val spoken = mutableListOf<String>()
        val dispatcher = FeedbackDispatcher(
            speaker = FeedbackDispatcher.Speaker { message, _, _ -> spoken += message },
            utteranceIdFactory = { "corridor-test-1" },
        )
        val pipeline = CorridorPipeline(
            stateMachine = CorridorStateMachine(confirmationsRequired = 1),
            feedbackDispatcher = dispatcher,
        )

        val result = pipeline.process(corridorGrid())

        assertEquals(CorridorCommand.STRAIGHT, result.state.command)
        assertNotNull(result.feedbackEvent)
        assertEquals("go_straight", result.feedbackEvent?.messageKey)
        assertEquals(listOf("Go straight"), spoken)
    }

    @Test
    fun failSafeStopSpeaksInitialStopForFrameLoss() {
        val spoken = mutableListOf<String>()
        val dispatcher = FeedbackDispatcher(
            speaker = FeedbackDispatcher.Speaker { message, _, _ -> spoken += message },
            utteranceIdFactory = { "corridor-test-1" },
        )
        val pipeline = CorridorPipeline(feedbackDispatcher = dispatcher)

        val result = pipeline.failSafeStop("frame_loss")

        assertEquals(CorridorCommand.STOP, result.decision.command)
        assertEquals("frame_loss", result.decision.reason)
        assertEquals(CorridorCommand.STOP, result.state.command)
        assertEquals("stop", result.feedbackEvent?.messageKey)
        assertEquals(listOf("Stop"), spoken)
    }

    @Test
    fun failSafeStopInterruptsConfirmedNonStopCommand() {
        val spoken = mutableListOf<String>()
        val dispatcher = FeedbackDispatcher(
            speaker = FeedbackDispatcher.Speaker { message, _, _ -> spoken += message },
            utteranceIdFactory = { "corridor-test-${spoken.size + 1}" },
        )
        val pipeline = CorridorPipeline(
            stateMachine = CorridorStateMachine(confirmationsRequired = 3),
            feedbackDispatcher = dispatcher,
        )
        val grid = corridorGrid()
        repeat(3) { pipeline.process(grid) }

        val result = pipeline.failSafeStop("low_confidence")

        assertEquals(CorridorCommand.STOP, result.decision.command)
        assertEquals(CorridorCommand.STOP, result.state.command)
        assertTrue(result.state.changed)
        assertEquals(listOf("Go straight", "Stop"), spoken)
    }

    private fun corridorGrid(): CorridorPlanner.DepthGrid {
        val grid = FloatArray(GRID_SIZE * GRID_SIZE) { 0.95f }
        repeat(GRID_SIZE) { offset ->
            val row = GRID_SIZE - 1 - offset
            for (col in 6..8) {
                grid[row * GRID_SIZE + col] = 0.30f
            }
        }
        return CorridorPlanner.DepthGrid.square15(grid)
    }

    private companion object {
        private const val GRID_SIZE = 15
    }
}
