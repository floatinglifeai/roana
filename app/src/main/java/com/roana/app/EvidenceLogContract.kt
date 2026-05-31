package com.roana.app

import java.util.Locale

object EvidenceLogContract {
    object Event {
        const val FRAME_STATS = "frame_stats"
        const val YOLO_TIMING = "yolo_timing"
        const val CORRIDOR_LIVE_TIMING = "corridor_live_timing"
        const val CORRIDOR_LIVE = "corridor_live"
        const val CORRIDOR_FEEDBACK = "corridor_feedback"
        const val DEBUG_SAFE_STOP_PROOF = "debug_safe_stop_proof"
    }

    fun corridorFeedback(event: FeedbackDispatcher.FeedbackEvent): String =
        "${Event.CORRIDOR_FEEDBACK} status=${if (event.spoken) "spoken" else "suppressed"} " +
            "id=${event.utteranceId ?: "none"} command=${event.command} " +
            "message=${event.messageKey} reason=${event.reason} " +
            "changed=${event.changed} forced=${event.forced} " +
            "pending=${event.pendingCommand ?: "none"} " +
            "pending_count=${event.pendingCount}"

    fun debugSafeStopProof(result: CorridorPipeline.CorridorFrameResult): String =
        "${Event.DEBUG_SAFE_STOP_PROOF} enabled=true reason=${result.decision.reason} " +
            "decision=${result.decision.command} state=${result.state.command}"

    fun frameStats(stats: FrameStatsLog): String =
        "${Event.FRAME_STATS} frames=${stats.frames} gap_count=${stats.gapCount} " +
            "analysis_ms=${stats.analysisMs.formatMs()} " +
            "inference_ms=${stats.yoloInferenceMs.formatMs()} " +
            "depth_ms=${stats.depthInferenceMs.formatMs()} " +
            "corridor=${stats.corridorCommand ?: "none"} " +
            "detection=${stats.detectionLabel ?: "none"} " +
            "image=${stats.imageWidth}x${stats.imageHeight}"

    fun yoloTiming(timing: YoloObstacleDetector.YoloTiming): String =
        "${Event.YOLO_TIMING} input_ms=${timing.inputMs.formatMs()} " +
            "model_ms=${timing.modelMs.formatMs()} " +
            "decode_ms=${timing.decodeMs.formatMs()} " +
            "total_ms=${timing.totalMs.formatMs()}"

    fun corridorLiveTiming(
        depthTiming: DepthAnythingRunner.DepthTiming,
        pipelineMs: Double,
        totalMs: Double,
    ): String =
        "${Event.CORRIDOR_LIVE_TIMING} depth_input_ms=${depthTiming.inputMs.formatMs()} " +
            "depth_model_ms=${depthTiming.inferenceMs.formatMs()} " +
            "depth_grid_ms=${depthTiming.outputGridMs.formatMs()} " +
            "pipeline_ms=${pipelineMs.formatMs()} " +
            "total_ms=${totalMs.formatMs()}"

    fun corridorLiveOk(
        depthMs: Double,
        result: CorridorPipeline.CorridorFrameResult,
        detections: Int,
    ): String =
        "${Event.CORRIDOR_LIVE} status=ok depth_ms=${depthMs.formatMs()} " +
            "decision=${result.decision.command} " +
            "state=${result.state.command} " +
            "reason=${result.decision.reason} " +
            "detections=$detections " +
            "path_cells=${result.decision.path.size}"

    fun corridorLiveFailed(reason: String, state: CorridorPlanner.CorridorCommand): String =
        "${Event.CORRIDOR_LIVE} status=failed reason=$reason state=$state"

    fun corridorLiveSafeStop(reason: String, state: CorridorStateMachine.CorridorState): String =
        "${Event.CORRIDOR_LIVE} status=safe_stop reason=$reason " +
            "state=${state.command} changed=${state.changed}"

    data class FrameStatsLog(
        val frames: Long,
        val gapCount: Long,
        val analysisMs: Double,
        val yoloInferenceMs: Double,
        val depthInferenceMs: Double,
        val corridorCommand: CorridorPlanner.CorridorCommand?,
        val detectionLabel: String?,
        val imageWidth: Int,
        val imageHeight: Int,
    )

    private fun Double.formatMs(): String =
        String.format(Locale.US, "%.2f", this)
}
