// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

package com.roana.app

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
    const val HUD_CAMERA_SCRIM = 0xAA06080C.toInt()
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
        0.00f to rgb(8, 24, 58),
        0.35f to rgb(12, 92, 120),
        0.55f to rgb(24, 150, 120),
        0.72f to rgb(180, 190, 60),
        0.86f to rgb(230, 140, 40),
        1.00f to rgb(220, 50, 50),
    )

    fun depthColor(value: Float): Int {
        val v = value.coerceIn(0f, 1f)
        for (i in 0 until rampStops.size - 1) {
            val (a, ca) = rampStops[i]
            val (b, cb) = rampStops[i + 1]
            if (v in a..b) {
                val f = if (b == a) 0f else (v - a) / (b - a)
                return rgb(
                    lerp(red(ca), red(cb), f),
                    lerp(green(ca), green(cb), f),
                    lerp(blue(ca), blue(cb), f),
                )
            }
        }
        return rampStops.last().second
    }

    private fun lerp(a: Int, b: Int, f: Float): Int = (a + (b - a) * f).toInt()
    private fun rgb(r: Int, g: Int, b: Int): Int = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
    private fun red(color: Int): Int = (color shr 16) and 0xFF
    private fun green(color: Int): Int = (color shr 8) and 0xFF
    private fun blue(color: Int): Int = color and 0xFF

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
    val source: Source = Source.LIVE,
) {
    enum class Source {
        LIVE,
        DEMO,
    }

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

        fun failSafeStop(
            state: CorridorStateMachine.CorridorState,
            frames: Long,
            yoloMs: Double,
            depthMs: Double,
            gaps: Long,
        ): PresentationFrame = PresentationFrame(
            command = CorridorCommand.STOP,
            reason = state.sourceDecision.reason,
            depth = FloatArray(RoanaPresentation.GRID * RoanaPresentation.GRID) { RoanaPresentation.NEAR_DEPTH },
            depthCols = RoanaPresentation.GRID,
            detections = emptyList(),
            frames = frames,
            yoloMs = yoloMs,
            depthMs = depthMs,
            gaps = gaps,
        )

        fun debugDemo(command: CorridorCommand, frame: Long): PresentationFrame {
            val values = FloatArray(RoanaPresentation.GRID * RoanaPresentation.GRID)
            for (row in 0 until RoanaPresentation.GRID) {
                for (col in 0 until RoanaPresentation.GRID) {
                    var value = 0.18f + row.toFloat() / RoanaPresentation.GRID * 0.34f
                    when (command) {
                        CorridorCommand.LEFT -> if (col >= 8 && row >= 4) value = 0.78f
                        CorridorCommand.RIGHT -> if (col <= 6 && row >= 4) value = 0.78f
                        CorridorCommand.STOP -> if (row >= RoanaPresentation.GRID - 4 && col in 5..9) value = 0.92f
                        CorridorCommand.STRAIGHT -> Unit
                    }
                    values[row * RoanaPresentation.GRID + col] = value.coerceIn(0f, 1f)
                }
            }

            return PresentationFrame(
                command = command,
                reason = if (command == CorridorCommand.STOP) {
                    CorridorContract.Reason.NEAR_OBSTACLE
                } else {
                    CorridorContract.Reason.PATH_FOUND
                },
                depth = values,
                depthCols = RoanaPresentation.GRID,
                detections = listOf(
                    DetectionBox(
                        label = "person",
                        score = 0.91f,
                        centerX = 0.62f,
                        centerY = 0.54f,
                        width = 0.22f,
                        height = 0.46f,
                    ),
                ),
                frames = frame,
                yoloMs = 21.0,
                depthMs = 14.0,
                gaps = 0,
                source = Source.DEMO,
            )
        }
    }
}
