package com.roana.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CorridorContractTest {
    @Test
    fun corridorConstantsMatchSharedParityContract() {
        assertEquals(15, CorridorContract.GRID_SIZE)
        assertEquals(0.86f, CorridorContract.NEAR_OBSTACLE_DEPTH)
        assertEquals(0.72f, CorridorContract.SAFE_CELL_DEPTH)
        assertEquals(0.12f, CorridorContract.MAX_FORWARD_DEPTH_RISE)
        assertEquals(6, CorridorContract.MIN_PATH_CELLS)
        assertEquals(3, CorridorContract.TURN_OFFSET_CELLS)
        assertEquals(3, CorridorContract.IMMINENT_OBSTACLE_ROWS)
        assertEquals(1, CorridorContract.IMMINENT_OBSTACLE_HALF_WIDTH)
        assertEquals(3, CorridorContract.DEFAULT_CONFIRMATIONS_REQUIRED)
        assertEquals(0.35f, CorridorContract.DETECTION_GRID_THRESHOLD)
        assertEquals(0.96f, CorridorContract.DETECTION_OBSTACLE_DEPTH)
    }

    @Test
    fun decisionReasonsMatchSharedParityContract() {
        assertEquals("path_found", CorridorContract.Reason.PATH_FOUND)
        assertEquals("near_obstacle", CorridorContract.Reason.NEAR_OBSTACLE)
        assertEquals("no_safe_corridor", CorridorContract.Reason.NO_SAFE_CORRIDOR)
        assertEquals("frame_loss", CorridorContract.Reason.FRAME_LOSS)
        assertEquals("low_confidence", CorridorContract.Reason.LOW_CONFIDENCE)
        assertTrue(CorridorContract.Reason.isEmergencyStop(CorridorContract.Reason.FRAME_LOSS))
        assertTrue(CorridorContract.Reason.isEmergencyStop(CorridorContract.Reason.LOW_CONFIDENCE))
    }

    @Test
    fun feedbackKeysMatchSharedParityContract() {
        assertEquals("turn_left", CorridorContract.Feedback.LEFT.messageKey)
        assertEquals("Turn left", CorridorContract.Feedback.LEFT.message)
        assertEquals("go_straight", CorridorContract.Feedback.STRAIGHT.messageKey)
        assertEquals("Go straight", CorridorContract.Feedback.STRAIGHT.message)
        assertEquals("turn_right", CorridorContract.Feedback.RIGHT.messageKey)
        assertEquals("Turn right", CorridorContract.Feedback.RIGHT.message)
        assertEquals("stop", CorridorContract.Feedback.STOP.messageKey)
        assertEquals("Stop", CorridorContract.Feedback.STOP.message)
    }
}
