package com.roana.app

import android.content.Context
import android.util.Log

class DepthAnythingSmoke(private val context: Context) {
    fun run(
        runPlanner: Boolean = false,
        onCorridorState: ((CorridorStateMachine.CorridorState) -> Unit)? = null,
    ) {
        val startedNs = System.nanoTime()
        val runner = DepthAnythingRunner(context)
        try {
            val loadMs = (System.nanoTime() - startedNs).toDouble() / NS_PER_MS
            Log.i(
                TAG,
                "depth_smoke status=loaded backend=${runner.backendName} " +
                    "input=${runner.inputShape.contentToString()} " +
                    "output=${runner.outputShape.contentToString()} load_ms=" +
                    "%.2f".format(java.util.Locale.US, loadMs),
            )
            if (runPlanner) {
                runPlannerSmoke(runner, onCorridorState)
            }
        } finally {
            runner.close()
        }
    }

    private fun runPlannerSmoke(
        runner: DepthAnythingRunner,
        onCorridorState: ((CorridorStateMachine.CorridorState) -> Unit)?,
    ) {
        val startedNs = System.nanoTime()
        val result = runner.infer(syntheticCorridorFrame())
        val pipeline = CorridorPipeline()
        var corridorResult = pipeline.process(result.depthMap)
        repeat(2) {
            corridorResult = pipeline.process(result.depthMap)
        }
        val elapsedMs = (System.nanoTime() - startedNs).toDouble() / NS_PER_MS
        Log.i(
            TAG,
            "depth_plan status=ok decision=${corridorResult.decision.command} " +
                "state=${corridorResult.state.command} " +
                "reason=${corridorResult.decision.reason} " +
                "path_cells=${corridorResult.decision.path.size} " +
                "depth_inference_ms=${"%.2f".format(java.util.Locale.US, result.inferenceMs)} " +
                "elapsed_ms=${"%.2f".format(java.util.Locale.US, elapsedMs)}",
        )
        onCorridorState?.invoke(corridorResult.state)
    }

    private fun syntheticCorridorFrame(): DepthFramePreprocessor.RgbFrame {
        val pixels = IntArray(DEPTH_INPUT_WIDTH * DEPTH_INPUT_HEIGHT)
        repeat(DEPTH_INPUT_HEIGHT) { row ->
            repeat(DEPTH_INPUT_WIDTH) { col ->
                val gradient = (row.toFloat() / (DEPTH_INPUT_HEIGHT - 1)).coerceIn(0f, 1f)
                val centerBias = 1f - kotlin.math.abs(col - DEPTH_INPUT_WIDTH / 2f) /
                    (DEPTH_INPUT_WIDTH / 2f)
                val red = ((0.2f + 0.5f * gradient).coerceIn(0f, 1f) * BYTE_MAX).toInt()
                val green = ((0.2f + 0.4f * centerBias).coerceIn(0f, 1f) * BYTE_MAX).toInt()
                val blue = ((0.1f + 0.4f * gradient).coerceIn(0f, 1f) * BYTE_MAX).toInt()
                pixels[row * DEPTH_INPUT_WIDTH + col] =
                    (red shl RED_SHIFT) or (green shl GREEN_SHIFT) or blue
            }
        }
        return DepthFramePreprocessor.RgbFrame(
            width = DEPTH_INPUT_WIDTH,
            height = DEPTH_INPUT_HEIGHT,
            pixels = pixels,
        )
    }

    private companion object {
        private const val TAG = "RoanaV0a"
        private const val NS_PER_MS = 1_000_000.0
        private const val DEPTH_INPUT_WIDTH = DepthAnythingTensor.INPUT_WIDTH
        private const val DEPTH_INPUT_HEIGHT = DepthAnythingTensor.INPUT_HEIGHT
        private const val RED_SHIFT = 16
        private const val GREEN_SHIFT = 8
        private const val BYTE_MAX = 255f
    }
}
