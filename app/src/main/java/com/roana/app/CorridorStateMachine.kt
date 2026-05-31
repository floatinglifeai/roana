package com.roana.app

import com.roana.app.CorridorPlanner.CorridorCommand
import com.roana.app.CorridorPlanner.CorridorDecision

class CorridorStateMachine(
    private val confirmationsRequired: Int = CorridorContract.DEFAULT_CONFIRMATIONS_REQUIRED,
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
        CorridorContract.Reason.isEmergencyStop(reason)

    data class CorridorState(
        val command: CorridorCommand,
        val sourceDecision: CorridorDecision,
        val pendingCommand: CorridorCommand?,
        val pendingCount: Int,
        val changed: Boolean,
    )
}
