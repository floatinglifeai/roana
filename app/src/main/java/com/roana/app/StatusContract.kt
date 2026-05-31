package com.roana.app

import java.util.Locale

object StatusContract {
    object Camera {
        const val WAITING = "Waiting for camera"
        const val STARTING = "Starting camera"
        const val ACTIVE = "Camera active"
        const val PERMISSION_REQUIRED = "Camera permission required"
        const val START_FAILED = "Camera start failed"
    }

    data class FrameSummary(
        val frames: Long,
        val yoloInferenceMs: Double,
        val gapCount: Long,
        val detectionLabel: String? = null,
        val detectionScorePercent: Int? = null,
        val corridorCommand: String? = null,
        val depthInferenceMs: Double? = null,
    )

    fun frameSummary(summary: FrameSummary): String {
        val detectionText = if (summary.detectionLabel != null && summary.detectionScorePercent != null) {
            " | ${summary.detectionLabel} ${summary.detectionScorePercent}%"
        } else {
            ""
        }
        val corridorText = if (summary.corridorCommand != null && summary.depthInferenceMs != null) {
            " | corridor ${summary.corridorCommand} ${summary.depthInferenceMs.roundMs()} ms"
        } else {
            ""
        }
        return "Frames ${summary.frames} | yolo ${summary.yoloInferenceMs.roundMs()} ms | " +
            "gaps ${summary.gapCount}$detectionText$corridorText"
    }

    private fun Double.roundMs(): Int =
        String.format(Locale.US, "%.0f", this).toInt()
}
