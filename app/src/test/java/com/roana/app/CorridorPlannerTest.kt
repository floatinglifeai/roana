package com.roana.app

import com.roana.app.CorridorPlanner.CorridorCommand
import com.roana.app.CorridorPlanner.DepthGrid
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CorridorPlannerTest {
    private val planner = CorridorPlanner()

    @Test
    fun choosesStraightForCenteredOpenCorridor() {
        val grid = baseBlockedGrid()
        carveCorridor(grid, listOf(7, 7, 7, 7, 7, 7, 7, 7, 7))

        val decision = planner.decide(DepthGrid.square15(grid))

        assertEquals(decision.toString(), CorridorCommand.STRAIGHT, decision.command)
        assertEquals("path_found", decision.reason)
        assertTrue(decision.path.size >= 6)
    }

    @Test
    fun choosesLeftForLeftBiasedCorridor() {
        val grid = baseBlockedGrid()
        carveCorridor(grid, listOf(7, 7, 7, 6, 5, 5, 4, 4, 4))

        val decision = planner.decide(DepthGrid.square15(grid))

        assertEquals(decision.toString(), CorridorCommand.LEFT, decision.command)
        assertEquals("path_found", decision.reason)
    }

    @Test
    fun choosesRightForRightBiasedCorridor() {
        val grid = baseBlockedGrid()
        carveCorridor(grid, listOf(7, 7, 7, 8, 9, 9, 10, 10, 10))

        val decision = planner.decide(DepthGrid.square15(grid))

        assertEquals(decision.toString(), CorridorCommand.RIGHT, decision.command)
        assertEquals("path_found", decision.reason)
    }

    @Test
    fun stopsForNearLowerHalfObstacle() {
        val grid = baseBlockedGrid()
        carveCorridor(grid, listOf(7, 7, 7, 7, 7, 7, 7, 7, 7))
        grid[index(row = 12, col = 7)] = 0.95f

        val decision = planner.decide(DepthGrid.square15(grid))

        assertEquals(decision.toString(), CorridorCommand.STOP, decision.command)
        assertEquals("near_obstacle", decision.reason)
    }

    @Test
    fun downsamplesDepthMapIntoPlannerGrid() {
        val depth = FloatArray(DEPTH_SIZE * DEPTH_SIZE) { 0.9f }
        val colStart = DEPTH_SIZE * 6 / GRID_SIZE
        val colEnd = DEPTH_SIZE * 9 / GRID_SIZE
        for (row in 0 until DEPTH_SIZE) {
            val normalizedForward = 0.35f - ((DEPTH_SIZE - 1 - row).toFloat() / DEPTH_SIZE) * 0.12f
            for (col in colStart until colEnd) {
                depth[row * DEPTH_SIZE + col] = normalizedForward
            }
        }

        val decision = planner.decide(
            DepthGrid.fromDepthMap(
                values = depth,
                rows = DEPTH_SIZE,
                cols = DEPTH_SIZE,
            ),
        )

        assertEquals(decision.toString(), CorridorCommand.STRAIGHT, decision.command)
        assertEquals("path_found", decision.reason)
    }

    @Test
    fun stateMachineRequiresThreeConfirmationsForNonStop() {
        val stateMachine = CorridorStateMachine(confirmationsRequired = 3)
        val straight = decision(CorridorCommand.STRAIGHT)

        assertEquals(CorridorCommand.STOP, stateMachine.update(straight).command)
        assertEquals(CorridorCommand.STOP, stateMachine.update(straight).command)
        val third = stateMachine.update(straight)

        assertEquals(CorridorCommand.STRAIGHT, third.command)
        assertTrue(third.changed)
    }

    @Test
    fun stateMachineStopsImmediately() {
        val stateMachine = CorridorStateMachine(confirmationsRequired = 3)
        repeat(3) { stateMachine.update(decision(CorridorCommand.RIGHT)) }

        val stop = stateMachine.update(decision(CorridorCommand.STOP))

        assertEquals(CorridorCommand.STOP, stop.command)
        assertTrue(stop.changed)
    }

    @Test
    fun stateMachineTreatsFrameLossAsStop() {
        val stateMachine = CorridorStateMachine(confirmationsRequired = 3)
        repeat(3) { stateMachine.update(decision(CorridorCommand.STRAIGHT)) }

        val stop = stateMachine.update(
            CorridorPlanner.CorridorDecision(
                command = CorridorCommand.STRAIGHT,
                path = emptyList(),
                reason = "frame_loss",
            ),
        )

        assertEquals(CorridorCommand.STOP, stop.command)
        assertTrue(stop.changed)
    }

    @Test
    fun stateMachineTreatsLowConfidenceAsStop() {
        val stateMachine = CorridorStateMachine(confirmationsRequired = 3)
        repeat(3) { stateMachine.update(decision(CorridorCommand.LEFT)) }

        val stop = stateMachine.update(
            CorridorPlanner.CorridorDecision(
                command = CorridorCommand.LEFT,
                path = emptyList(),
                reason = "low_confidence",
            ),
        )

        assertEquals(CorridorCommand.STOP, stop.command)
        assertTrue(stop.changed)
    }

    private fun baseBlockedGrid(): FloatArray =
        FloatArray(GRID_SIZE * GRID_SIZE) { 0.95f }

    private fun carveCorridor(grid: FloatArray, colsFromBottom: List<Int>) {
        colsFromBottom.forEachIndexed { offset, col ->
            val row = GRID_SIZE - 1 - offset
            for (safeCol in (col - 1)..(col + 1)) {
                if (safeCol in 0 until GRID_SIZE) {
                    grid[index(row, safeCol)] = 0.35f - offset * 0.02f
                }
            }
        }
    }

    private fun index(row: Int, col: Int): Int = row * GRID_SIZE + col

    private fun decision(command: CorridorCommand): CorridorPlanner.CorridorDecision =
        CorridorPlanner.CorridorDecision(command = command, path = emptyList(), reason = "test")

    private companion object {
        private const val GRID_SIZE = 15
        private const val DEPTH_SIZE = 518
    }
}
