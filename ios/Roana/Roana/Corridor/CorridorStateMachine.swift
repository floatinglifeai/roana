// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

final class CorridorStateMachine {
    private let confirmationsRequired: Int
    private var currentCommand = CorridorCommand.stop
    private var pendingCommand: CorridorCommand?
    private var pendingCount = 0

    init(confirmationsRequired: Int = 3) {
        precondition(confirmationsRequired > 0, "confirmationsRequired must be positive")
        self.confirmationsRequired = confirmationsRequired
    }

    func update(decision: CorridorDecision) -> CorridorState {
        let proposedCommand = decision.requiresEmergencyStop ? CorridorCommand.stop : decision.command
        if proposedCommand == currentCommand {
            pendingCommand = nil
            pendingCount = 0
            return state(decision: decision, changed: false)
        }

        if proposedCommand == .stop {
            currentCommand = .stop
            pendingCommand = nil
            pendingCount = 0
            return state(decision: decision, changed: true)
        }

        if pendingCommand == proposedCommand {
            pendingCount += 1
        } else {
            pendingCommand = proposedCommand
            pendingCount = 1
        }

        if pendingCount >= confirmationsRequired {
            currentCommand = proposedCommand
            pendingCommand = nil
            pendingCount = 0
            return state(decision: decision, changed: true)
        }

        return state(decision: decision, changed: false)
    }

    private func state(decision: CorridorDecision, changed: Bool) -> CorridorState {
        CorridorState(
            command: currentCommand,
            sourceDecision: decision,
            pendingCommand: pendingCommand,
            pendingCount: pendingCount,
            changed: changed,
        )
    }
}

struct CorridorState: Equatable {
    let command: CorridorCommand
    let sourceDecision: CorridorDecision
    let pendingCommand: CorridorCommand?
    let pendingCount: Int
    let changed: Bool
}

private extension CorridorDecision {
    var requiresEmergencyStop: Bool {
        reason == "frame_loss" || reason == "low_confidence"
    }
}
