package com.roana.app

import com.roana.app.CorridorPlanner.CorridorCommand
import org.junit.Assert.assertEquals
import org.junit.Test

class EvidenceLogContractTest {
    @Test
    fun corridorFeedbackKeepsVerifierCompatibleFields() {
        val event = FeedbackDispatcher.FeedbackEvent(
            command = CorridorCommand.STOP,
            messageKey = CorridorContract.Feedback.STOP.messageKey,
            reason = CorridorContract.Reason.LOW_CONFIDENCE,
            changed = true,
            forced = true,
            spoken = true,
            utteranceId = "roana-corridor-1",
            pendingCommand = null,
            pendingCount = 0,
        )

        assertEquals(
            "corridor_feedback status=spoken id=roana-corridor-1 command=STOP " +
                "message=stop reason=low_confidence changed=true forced=true " +
                "pending=none pending_count=0",
            EvidenceLogContract.corridorFeedback(event),
        )
    }

    @Test
    fun frameStatsKeepsVerifierCompatibleFields() {
        val line = EvidenceLogContract.frameStats(
            EvidenceLogContract.FrameStatsLog(
                frames = 5,
                gapCount = 0,
                analysisMs = 11.0,
                yoloInferenceMs = 7.5,
                depthInferenceMs = 82.25,
                corridorCommand = CorridorCommand.STRAIGHT,
                detectionLabel = "person",
                imageWidth = 1280,
                imageHeight = 720,
            ),
        )

        assertEquals(
            "frame_stats frames=5 gap_count=0 analysis_ms=11.00 inference_ms=7.50 " +
                "depth_ms=82.25 corridor=STRAIGHT detection=person image=1280x720",
            line,
        )
    }

    @Test
    fun corridorLiveOkKeepsVerifierCompatibleFields() {
        val result = CorridorPipeline.CorridorFrameResult(
            decision = CorridorPlanner.CorridorDecision(
                command = CorridorCommand.STRAIGHT,
                path = listOf(CorridorPlanner.Cell(row = 14, col = 7)),
                reason = CorridorContract.Reason.PATH_FOUND,
            ),
            state = CorridorStateMachine.CorridorState(
                command = CorridorCommand.STRAIGHT,
                sourceDecision = CorridorPlanner.CorridorDecision(
                    command = CorridorCommand.STRAIGHT,
                    path = emptyList(),
                    reason = CorridorContract.Reason.PATH_FOUND,
                ),
                pendingCommand = null,
                pendingCount = 0,
                changed = true,
            ),
            feedbackEvent = null,
        )

        assertEquals(
            "corridor_live status=ok depth_ms=88.20 decision=STRAIGHT state=STRAIGHT " +
                "reason=path_found detections=1 path_cells=1",
            EvidenceLogContract.corridorLiveOk(depthMs = 88.2, result = result, detections = 1),
        )
    }
}
