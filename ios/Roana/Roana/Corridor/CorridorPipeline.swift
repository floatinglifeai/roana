// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

final class CorridorPipeline {
    private let planner: CorridorPlanner
    private let stateMachine: CorridorStateMachine
    private let gridFusion: CorridorGridFusion
    private let feedbackDispatcher: CorridorFeedbackDispatcher?
    private let lock = NSLock()

    init(
        planner: CorridorPlanner = CorridorPlanner(),
        stateMachine: CorridorStateMachine = CorridorStateMachine(),
        gridFusion: CorridorGridFusion = CorridorGridFusion(),
        feedbackDispatcher: CorridorFeedbackDispatcher? = nil,
    ) {
        self.planner = planner
        self.stateMachine = stateMachine
        self.gridFusion = gridFusion
        self.feedbackDispatcher = feedbackDispatcher
    }

    func process(
        grid: DepthGrid,
        detections: [CorridorDetection] = [],
        forceFeedback: Bool = false,
    ) -> CorridorFrameResult {
        let decision = planner.decide(grid: gridFusion.fuse(depthGrid: grid, detections: detections))
        return applyDecision(decision, forceFeedback: forceFeedback)
    }

    func failSafeStop(reason: String, forceFeedback: Bool = false) -> CorridorFrameResult {
        let decision = CorridorDecision(command: .stop, path: [], reason: reason)
        return applyDecision(decision, forceFeedback: forceFeedback)
    }

    private func applyDecision(_ decision: CorridorDecision, forceFeedback: Bool) -> CorridorFrameResult {
        lock.lock()
        defer {
            lock.unlock()
        }

        let state = stateMachine.update(decision: decision)
        print(
            "roana_ios_corridor decision=\(decision.command.rawValue) state=\(state.command.rawValue) " +
                "reason=\(decision.reason) path_cells=\(decision.path.count) " +
                "pending=\(state.pendingCommand?.rawValue ?? "none") pending_count=\(state.pendingCount)",
        )
        return CorridorFrameResult(
            decision: decision,
            state: state,
            feedbackEvent: feedbackDispatcher?.dispatch(state: state, force: forceFeedback),
        )
    }
}

struct CorridorFrameResult: Equatable {
    let decision: CorridorDecision
    let state: CorridorState
    let feedbackEvent: CorridorFeedbackDispatcher.Event?
}
