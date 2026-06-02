// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

package com.roana.app

import android.graphics.Color
import com.roana.app.CorridorPlanner.CorridorCommand

/**
 * Android mirror of parity/presentation-core.json. The JSON is the source of
 * truth; keep these values in sync and let the presentation parity test catch
 * drift. Depth thresholds are read from [CorridorContract], never re-declared.
 */
object RoanaPresentation {

    /** Grid edge length, aligned to the planner grid. */
    const val GRID = CorridorContract.GRID_SIZE

    /** Thresholds reused from the corridor contract (no magic numbers in UI). */
    const val SAFE_DEPTH = CorridorContract.SAFE_CELL_DEPTH
    const val NEAR_DEPTH = CorridorContract.NEAR_OBSTACLE_DEPTH

    const val DETECTION_STROKE = 0xFF3AD6C0.toInt()
    const val HUD_BACKGROUND = 0xFF06080C.toInt()
    const val AMBIENT_BACKGROUND = 0xFF03050A.toInt()
    const val STOP_EDGE = 0xFFFF5563.toInt()

    data class CommandStyle(
        val glyph: String,
        val color: Int,
        val caption: String,
        val pathTargetCol: Int,
    )

    fun styleFor(command: CorridorCommand): CommandStyle = when (command) {
        CorridorCommand.STRAIGHT -> CommandStyle("↑", 0xFF62E08A.toInt(), "Go straight", 7)
        CorridorCommand.LEFT -> CommandStyle("←", 0xFF5CC8FF.toInt(), "Turn left", 4)
        CorridorCommand.RIGHT -> CommandStyle("→", 0xFFC89BFF.toInt(), "Turn right", 10)
        CorridorCommand.STOP -> CommandStyle("■", 0xFFFF5563.toInt(), "Stop", 7)
    }

    /** Far -> near = cool -> warm. Stops sit on the corridor thresholds. */
    private val rampStops = listOf(
        0.00f to Color.rgb(8, 24, 58),
        0.35f to Color.rgb(12, 92, 120),
        0.55f to Color.rgb(24, 150, 120),
        0.72f to Color.rgb(180, 190, 60),
        0.86f to Color.rgb(230, 140, 40),
        1.00f to Color.rgb(220, 50, 50),
    )

    fun depthColor(value: Float): Int {
        val v = value.coerceIn(0f, 1f)
        for (i in 0 until rampStops.size - 1) {
            val (a, ca) = rampStops[i]
            val (b, cb) = rampStops[i + 1]
            if (v in a..b) {
                val f = if (b == a) 0f else (v - a) / (b - a)
                return Color.rgb(
                    lerp(Color.red(ca), Color.red(cb), f),
                    lerp(Color.green(ca), Color.green(cb), f),
                    lerp(Color.blue(ca), Color.blue(cb), f),
                )
            }
        }
        return rampStops.last().second
    }

    private fun lerp(a: Int, b: Int, f: Float): Int = (a + (b - a) * f).toInt()

    /** Gesture: bottom-right corner long-press. */
    const val GESTURE_REGION_DP = 88f
    const val GESTURE_HOLD_MS = 2000L
}

/** Normalized obstacle box (0..1), decoupled from YoloDetection. */
data class DetectionBox(
    val label: String,
    val score: Float,
    val centerX: Float,
    val centerY: Float,
    val width: Float,
    val height: Float,
)

/** Everything an overlay needs for one frame. Built at the inference site. */
data class PresentationFrame(
    val command: CorridorPlanner.CorridorCommand,
    val reason: String,
    val depth: FloatArray,        // size GRID*GRID, row-major, normalized 0..1
    val depthCols: Int,
    val detections: List<DetectionBox>,
    val frames: Long,
    val yoloMs: Double,
    val depthMs: Double,
    val gaps: Long,
) {
    fun depthAt(row: Int, col: Int): Float = depth[row * depthCols + col]

    fun telemetry(): List<Pair<String, String>> = listOf(
        "FRM" to frames.toString(),
        "YOLO ms" to yoloMs.toInt().toString(),
        "DEPTH ms" to depthMs.toInt().toString(),
        "GAPS" to gaps.toString(),
    )

    companion object {
        /** Adapter from the live corridor/detection types already in the app. */
        fun from(
            grid: CorridorPlanner.DepthGrid,
            detections: List<YoloObstacleDetector.YoloDetection>,
            state: CorridorStateMachine.CorridorState,
            frames: Long,
            yoloMs: Double,
            depthMs: Double,
            gaps: Long,
        ): PresentationFrame = PresentationFrame(
            command = state.command,
            reason = state.sourceDecision.reason,
            depth = grid.toFloatArray(),
            depthCols = grid.cols,
            detections = detections.map {
                DetectionBox(it.label, it.score, it.centerX, it.centerY, it.width, it.height)
            },
            frames = frames,
            yoloMs = yoloMs,
            depthMs = depthMs,
            gaps = gaps,
        )
    }
}
