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
