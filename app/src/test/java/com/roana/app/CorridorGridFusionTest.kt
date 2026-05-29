package com.roana.app

import com.roana.app.CorridorPlanner.CorridorCommand
import org.junit.Assert.assertEquals
import org.junit.Test

class CorridorGridFusionTest {
    @Test
    fun highConfidenceCenterDetectionForcesNearObstacleStop() {
        val depthMap = openDepthMap()
        val detection = YoloObstacleDetector.YoloDetection(
            label = "person",
            score = 0.92f,
            centerX = 0.5f,
            centerY = 0.84f,
            width = 0.25f,
            height = 0.24f,
        )

        val grid = CorridorGridFusion().fuse(depthMap, listOf(detection))
        val decision = CorridorPlanner().decide(grid)

        assertEquals(CorridorCommand.STOP, decision.command)
        assertEquals("near_obstacle", decision.reason)
    }

    @Test
    fun lowConfidenceDetectionDoesNotOverrideDepthCorridor() {
        val depthMap = openDepthMap()
        val detection = YoloObstacleDetector.YoloDetection(
            label = "person",
            score = 0.20f,
            centerX = 0.5f,
            centerY = 0.84f,
            width = 0.25f,
            height = 0.24f,
        )

        val result = CorridorPipeline(
            stateMachine = CorridorStateMachine(confirmationsRequired = 1),
        ).process(depthMap, detections = listOf(detection))

        assertEquals(CorridorCommand.STRAIGHT, result.state.command)
    }

    private fun openDepthMap(): DepthAnythingTensor.DepthMap {
        val values = FloatArray(DEPTH_SIZE * DEPTH_SIZE) { 0.9f }
        val colStart = DEPTH_SIZE * 6 / GRID_SIZE
        val colEnd = DEPTH_SIZE * 9 / GRID_SIZE
        for (row in 0 until DEPTH_SIZE) {
            val normalizedForward = 0.35f - ((DEPTH_SIZE - 1 - row).toFloat() / DEPTH_SIZE) * 0.12f
            for (col in colStart until colEnd) {
                values[row * DEPTH_SIZE + col] = normalizedForward
            }
        }
        return DepthAnythingTensor.DepthMap(rows = DEPTH_SIZE, cols = DEPTH_SIZE, values = values)
    }

    private companion object {
        private const val GRID_SIZE = 15
        private const val DEPTH_SIZE = 518
    }
}
