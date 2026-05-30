// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

final class CorridorPipeline {
    private let planner: CorridorPlanner
    private let stateMachine: CorridorStateMachine
    private let gridFusion: CorridorGridFusion

    init(
        planner: CorridorPlanner = CorridorPlanner(),
        stateMachine: CorridorStateMachine = CorridorStateMachine(),
        gridFusion: CorridorGridFusion = CorridorGridFusion(),
    ) {
        self.planner = planner
        self.stateMachine = stateMachine
        self.gridFusion = gridFusion
    }

    func process(
        grid: DepthGrid,
        detections: [CorridorDetection] = [],
    ) -> CorridorFrameResult {
        let decision = planner.decide(grid: gridFusion.fuse(depthGrid: grid, detections: detections))
        return applyDecision(decision)
    }

    func failSafeStop(reason: String) -> CorridorFrameResult {
        let decision = CorridorDecision(command: .stop, path: [], reason: reason)
        return applyDecision(decision)
    }

    private func applyDecision(_ decision: CorridorDecision) -> CorridorFrameResult {
        let state = stateMachine.update(decision: decision)
        print(
            "roana_ios_corridor decision=\(decision.command.rawValue) state=\(state.command.rawValue) " +
                "reason=\(decision.reason) path_cells=\(decision.path.count) " +
                "pending=\(state.pendingCommand?.rawValue ?? "none") pending_count=\(state.pendingCount)",
        )
        return CorridorFrameResult(decision: decision, state: state)
    }
}

struct CorridorFrameResult: Equatable {
    let decision: CorridorDecision
    let state: CorridorState
}
