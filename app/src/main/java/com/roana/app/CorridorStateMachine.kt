package com.roana.app

import com.roana.app.CorridorPlanner.CorridorCommand
import com.roana.app.CorridorPlanner.CorridorDecision

class CorridorStateMachine(
    private val confirmationsRequired: Int = DEFAULT_CONFIRMATIONS_REQUIRED,
) {
    private var currentCommand = CorridorCommand.STOP
    private var pendingCommand: CorridorCommand? = null
    private var pendingCount = 0

    init {
        require(confirmationsRequired > 0) { "confirmationsRequired must be positive" }
    }

    fun update(decision: CorridorDecision): CorridorState {
        val proposedCommand = if (decision.requiresEmergencyStop()) {
            CorridorCommand.STOP
        } else {
            decision.command
        }
        if (proposedCommand == currentCommand) {
            pendingCommand = null
            pendingCount = 0
            return state(decision, changed = false)
        }

        if (proposedCommand == CorridorCommand.STOP) {
            currentCommand = CorridorCommand.STOP
            pendingCommand = null
            pendingCount = 0
            return state(decision, changed = true)
        }

        if (pendingCommand == proposedCommand) {
            pendingCount += 1
        } else {
            pendingCommand = proposedCommand
            pendingCount = 1
        }

        if (pendingCount >= confirmationsRequired) {
            currentCommand = proposedCommand
            pendingCommand = null
            pendingCount = 0
            return state(decision, changed = true)
        }

        return state(decision, changed = false)
    }

    private fun state(decision: CorridorDecision, changed: Boolean): CorridorState =
        CorridorState(
            command = currentCommand,
            sourceDecision = decision,
            pendingCommand = pendingCommand,
            pendingCount = pendingCount,
            changed = changed,
        )

    private fun CorridorDecision.requiresEmergencyStop(): Boolean =
        reason == REASON_FRAME_LOSS || reason == REASON_LOW_CONFIDENCE

    data class CorridorState(
        val command: CorridorCommand,
        val sourceDecision: CorridorDecision,
        val pendingCommand: CorridorCommand?,
        val pendingCount: Int,
        val changed: Boolean,
    )

    private companion object {
        private const val DEFAULT_CONFIRMATIONS_REQUIRED = 3
        private const val REASON_FRAME_LOSS = "frame_loss"
        private const val REASON_LOW_CONFIDENCE = "low_confidence"
    }
}
