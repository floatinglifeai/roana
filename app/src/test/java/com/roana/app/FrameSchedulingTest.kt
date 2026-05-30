package com.roana.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FrameSchedulingTest {
    @Test
    fun everyFrameIntervalRunsEveryPositiveFrame() {
        assertFalse(shouldRunPeriodicFrame(frame = 0, interval = 1))
        assertTrue(shouldRunPeriodicFrame(frame = 1, interval = 1))
        assertTrue(shouldRunPeriodicFrame(frame = 2, interval = 1))
        assertTrue(shouldRunPeriodicFrame(frame = 3, interval = 1))
    }

    @Test
    fun largerIntervalRunsOnOneBasedCadence() {
        assertTrue(shouldRunPeriodicFrame(frame = 1, interval = 10))
        assertFalse(shouldRunPeriodicFrame(frame = 2, interval = 10))
        assertFalse(shouldRunPeriodicFrame(frame = 10, interval = 10))
        assertTrue(shouldRunPeriodicFrame(frame = 11, interval = 10))
    }
}
