package com.roana.app

class CorridorPipeline(
    private val planner: CorridorPlanner = CorridorPlanner(),
    private val stateMachine: CorridorStateMachine = CorridorStateMachine(),
    private val feedbackDispatcher: FeedbackDispatcher? = null,
    private val gridFusion: CorridorGridFusion = CorridorGridFusion(),
) {
    fun process(
        depthMap: DepthAnythingTensor.DepthMap,
        detections: List<YoloObstacleDetector.YoloDetection> = emptyList(),
        forceFeedback: Boolean = false,
    ): CorridorFrameResult =
        process(gridFusion.fuse(depthMap, detections), forceFeedback)

    fun process(
        grid: CorridorPlanner.DepthGrid,
        forceFeedback: Boolean = false,
    ): CorridorFrameResult {
        val decision = planner.decide(grid)
        return applyDecision(decision, forceFeedback)
    }

    fun failSafeStop(
        reason: String,
        forceFeedback: Boolean = false,
    ): CorridorFrameResult {
        val decision = CorridorPlanner.CorridorDecision(
            command = CorridorPlanner.CorridorCommand.STOP,
            path = emptyList(),
            reason = reason,
        )
        return applyDecision(decision, forceFeedback)
    }

    private fun applyDecision(
        decision: CorridorPlanner.CorridorDecision,
        forceFeedback: Boolean,
    ): CorridorFrameResult {
        val state = stateMachine.update(decision)
        return CorridorFrameResult(
            decision = decision,
            state = state,
            feedbackEvent = feedbackDispatcher?.dispatch(state, force = forceFeedback),
        )
    }

    data class CorridorFrameResult(
        val decision: CorridorPlanner.CorridorDecision,
        val state: CorridorStateMachine.CorridorState,
        val feedbackEvent: FeedbackDispatcher.FeedbackEvent?,
    )
}
