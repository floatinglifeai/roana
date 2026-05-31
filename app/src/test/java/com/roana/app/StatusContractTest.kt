package com.roana.app

import org.junit.Assert.assertEquals
import org.junit.Test

class StatusContractTest {
    @Test
    fun cameraStatusTextMatchesNativeAndroidSurface() {
        assertEquals("Waiting for camera", StatusContract.Camera.WAITING)
        assertEquals("Starting camera", StatusContract.Camera.STARTING)
        assertEquals("Camera active", StatusContract.Camera.ACTIVE)
        assertEquals("Camera permission required", StatusContract.Camera.PERMISSION_REQUIRED)
        assertEquals("Camera start failed", StatusContract.Camera.START_FAILED)
    }

    @Test
    fun frameSummaryKeepsExistingAndroidStatusShape() {
        val text = StatusContract.frameSummary(
            StatusContract.FrameSummary(
                frames = 42,
                yoloInferenceMs = 12.4,
                gapCount = 1,
                detectionLabel = "person",
                detectionScorePercent = 91,
                corridorCommand = "STRAIGHT",
                depthInferenceMs = 83.6,
            ),
        )

        assertEquals("Frames 42 | yolo 12 ms | gaps 1 | person 91% | corridor STRAIGHT 84 ms", text)
    }
}
