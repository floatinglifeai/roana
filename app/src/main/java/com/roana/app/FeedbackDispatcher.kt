package com.roana.app

import com.roana.app.CorridorPlanner.CorridorCommand
import com.roana.app.CorridorStateMachine.CorridorState

class FeedbackDispatcher(
    private val speaker: Speaker,
    private val logger: (FeedbackEvent) -> Unit = {},
    private val utteranceIdFactory: () -> String,
) {
    private var hasSpoken = false

    fun dispatch(state: CorridorState, force: Boolean = false): FeedbackEvent {
        val feedback = feedbackFor(state.command)
        val shouldSpeak = force || state.changed || (!hasSpoken && state.requiresInitialStopFeedback())
        val utteranceId = if (shouldSpeak) utteranceIdFactory() else null

        if (shouldSpeak && utteranceId != null) {
            speaker.speak(feedback.message, QueueMode.FLUSH, utteranceId)
            hasSpoken = true
        }

        return FeedbackEvent(
            command = state.command,
            messageKey = feedback.messageKey,
            reason = state.sourceDecision.reason,
            changed = state.changed,
            forced = force,
            spoken = shouldSpeak,
            utteranceId = utteranceId,
            pendingCommand = state.pendingCommand,
            pendingCount = state.pendingCount,
        ).also(logger)
    }

    private fun CorridorState.requiresInitialStopFeedback(): Boolean =
        command == CorridorCommand.STOP &&
            (
                sourceDecision.command == CorridorCommand.STOP ||
                    sourceDecision.reason == REASON_FRAME_LOSS ||
                    sourceDecision.reason == REASON_LOW_CONFIDENCE
                )

    private fun feedbackFor(command: CorridorCommand): CommandFeedback =
        when (command) {
            CorridorCommand.LEFT -> CommandFeedback(message = "Turn left", messageKey = "turn_left")
            CorridorCommand.STRAIGHT -> CommandFeedback(message = "Go straight", messageKey = "go_straight")
            CorridorCommand.RIGHT -> CommandFeedback(message = "Turn right", messageKey = "turn_right")
            CorridorCommand.STOP -> CommandFeedback(message = "Stop", messageKey = "stop")
        }

    fun interface Speaker {
        fun speak(message: String, queueMode: QueueMode, utteranceId: String)
    }

    enum class QueueMode {
        FLUSH,
    }

    data class FeedbackEvent(
        val command: CorridorCommand,
        val messageKey: String,
        val reason: String,
        val changed: Boolean,
        val forced: Boolean,
        val spoken: Boolean,
        val utteranceId: String?,
        val pendingCommand: CorridorCommand?,
        val pendingCount: Int,
    )

    private data class CommandFeedback(
        val message: String,
        val messageKey: String,
    )

    private companion object {
        private const val REASON_FRAME_LOSS = "frame_loss"
        private const val REASON_LOW_CONFIDENCE = "low_confidence"
    }
}
