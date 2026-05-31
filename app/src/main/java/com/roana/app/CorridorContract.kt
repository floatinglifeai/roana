package com.roana.app

object CorridorContract {
    const val GRID_SIZE = 15
    const val NEAR_OBSTACLE_DEPTH = 0.86f
    const val SAFE_CELL_DEPTH = 0.72f
    const val MAX_FORWARD_DEPTH_RISE = 0.12f
    const val MIN_PATH_CELLS = 6
    const val TURN_OFFSET_CELLS = 3
    const val IMMINENT_OBSTACLE_ROWS = 3
    const val IMMINENT_OBSTACLE_HALF_WIDTH = 1
    const val DEFAULT_CONFIRMATIONS_REQUIRED = 3
    const val DETECTION_GRID_THRESHOLD = 0.35f
    const val DETECTION_OBSTACLE_DEPTH = 0.96f

    object Reason {
        const val PATH_FOUND = "path_found"
        const val NEAR_OBSTACLE = "near_obstacle"
        const val NO_SAFE_CORRIDOR = "no_safe_corridor"
        const val FRAME_LOSS = "frame_loss"
        const val LOW_CONFIDENCE = "low_confidence"

        fun isEmergencyStop(reason: String): Boolean =
            reason == FRAME_LOSS || reason == LOW_CONFIDENCE
    }

    enum class Feedback(
        val message: String,
        val messageKey: String,
    ) {
        LEFT(message = "Turn left", messageKey = "turn_left"),
        STRAIGHT(message = "Go straight", messageKey = "go_straight"),
        RIGHT(message = "Turn right", messageKey = "turn_right"),
        STOP(message = "Stop", messageKey = "stop"),
    }
}
