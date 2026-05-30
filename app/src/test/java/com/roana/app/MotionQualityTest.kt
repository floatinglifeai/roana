package com.roana.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MotionQualityTest {
    @Test
    fun stableSampleTrustsGuidance() {
        val quality = MotionQualityClassifier.classify(
            MotionQualitySample(
                pitchDegrees = -10.0,
                angularVelocityDegreesPerSecond = 20.0,
            ),
        )

        assertEquals(MotionQuality.Label.STABLE, quality.label)
        assertEquals("stable", quality.label.logValue)
        assertEquals("motion_stable", quality.reason)
        assertTrue(quality.trustsGuidance)
    }

    @Test
    fun missingMotionKeepsImageOnlyGuidanceAvailable() {
        val quality = MotionQualityClassifier.classify(null)

        assertEquals(MotionQuality.Label.STABLE, quality.label)
        assertEquals("motion_unavailable", quality.reason)
        assertTrue(quality.trustsGuidance)
    }

    @Test
    fun lowPitchIsPointingDown() {
        val quality = MotionQualityClassifier.classify(
            MotionQualitySample(
                pitchDegrees = -60.0,
                angularVelocityDegreesPerSecond = 10.0,
            ),
        )

        assertEquals(MotionQuality.Label.POINTING_DOWN, quality.label)
        assertEquals("pointing_down", quality.label.logValue)
        assertEquals("pitch_down", quality.reason)
        assertFalse(quality.trustsGuidance)
    }

    @Test
    fun highAngularVelocityIsUnstable() {
        val positive = MotionQualityClassifier.classify(
            MotionQualitySample(
                pitchDegrees = -20.0,
                angularVelocityDegreesPerSecond = 130.0,
            ),
        )
        val negative = MotionQualityClassifier.classify(
            MotionQualitySample(
                pitchDegrees = -20.0,
                angularVelocityDegreesPerSecond = -130.0,
            ),
        )

        assertEquals(MotionQuality.Label.UNSTABLE, positive.label)
        assertEquals(MotionQuality.Label.UNSTABLE, negative.label)
        assertEquals("unstable", positive.label.logValue)
        assertEquals("high_angular_velocity", positive.reason)
        assertFalse(positive.trustsGuidance)
    }
}
