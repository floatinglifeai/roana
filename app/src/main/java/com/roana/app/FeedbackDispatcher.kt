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
                    CorridorContract.Reason.isEmergencyStop(sourceDecision.reason)
                )

    private fun feedbackFor(command: CorridorCommand): CommandFeedback =
        when (command) {
            CorridorCommand.LEFT -> CorridorContract.Feedback.LEFT.toCommandFeedback()
            CorridorCommand.STRAIGHT -> CorridorContract.Feedback.STRAIGHT.toCommandFeedback()
            CorridorCommand.RIGHT -> CorridorContract.Feedback.RIGHT.toCommandFeedback()
            CorridorCommand.STOP -> CorridorContract.Feedback.STOP.toCommandFeedback()
        }

    private fun CorridorContract.Feedback.toCommandFeedback(): CommandFeedback =
        CommandFeedback(message = message, messageKey = messageKey)

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

}
