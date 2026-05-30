// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

@discardableResult
func expect(_ condition: @autoclosure () -> Bool, _ message: String) -> Bool {
    if !condition() {
        fputs("CorridorCoreSmoke failed: \(message)\n", stderr)
        exit(1)
    }
    return true
}

func grid(_ fill: Float = 0.2) -> DepthGrid {
    DepthGrid.square15(Array(repeating: fill, count: CorridorConstants.gridSize * CorridorConstants.gridSize))
}

func baseBlockedGrid() -> [Float] {
    Array(repeating: 0.95, count: CorridorConstants.gridSize * CorridorConstants.gridSize)
}

func carveCorridor(_ values: inout [Float], colsFromBottom: [Int]) {
    for (offset, col) in colsFromBottom.enumerated() {
        let row = CorridorConstants.gridSize - 1 - offset
        for safeCol in (col - 1)...(col + 1) where (0..<CorridorConstants.gridSize).contains(safeCol) {
            values[row * CorridorConstants.gridSize + safeCol] = 0.35 - Float(offset) * 0.02
        }
    }
}

func gridWithNearObstacle() -> DepthGrid {
    var values = baseBlockedGrid()
    carveCorridor(&values, colsFromBottom: [7, 7, 7, 7, 7, 7, 7, 7, 7])
    values[12 * CorridorConstants.gridSize + 7] = 0.95
    return DepthGrid.square15(values)
}

func gridWithLeftCorridor() -> DepthGrid {
    var values = baseBlockedGrid()
    carveCorridor(&values, colsFromBottom: [7, 7, 7, 6, 5, 5, 4, 4, 4])
    return DepthGrid.square15(values)
}

let planner = CorridorPlanner()

let straight = planner.decide(grid: grid())
expect(straight.command == .straight, "all-safe grid should go straight")
expect(straight.reason == "path_found", "all-safe grid should find a path")

let near = planner.decide(grid: gridWithNearObstacle())
expect(near.command == .stop, "near bottom-center obstacle should stop")
expect(near.reason == "near_obstacle", "near obstacle reason should be preserved")

let left = planner.decide(grid: gridWithLeftCorridor())
expect(left.command == .left, "left corridor should choose left")

let stateMachine = CorridorStateMachine()
let rightDecision = CorridorDecision(command: .right, path: straight.path, reason: "path_found")
expect(stateMachine.update(decision: rightDecision).command == .stop, "first right frame should remain stop")
expect(stateMachine.update(decision: rightDecision).command == .stop, "second right frame should remain stop")
let confirmedRight = stateMachine.update(decision: rightDecision)
expect(confirmedRight.command == .right, "third right frame should confirm right")
expect(confirmedRight.changed, "confirmed right should report changed")

let failSafe = stateMachine.update(
    decision: CorridorDecision(command: .straight, path: [], reason: "low_confidence"),
)
expect(failSafe.command == .stop, "low confidence should force stop")
expect(failSafe.changed, "low confidence stop should report changed from right")

let fused = CorridorGridFusion().fuse(
    depthGrid: {
        var values = baseBlockedGrid()
        carveCorridor(&values, colsFromBottom: [7, 7, 7, 7, 7, 7, 7, 7, 7])
        return DepthGrid.square15(values)
    }(),
    detections: [
        CorridorDetection(
            confidence: 0.9,
            centerX: 0.5,
            centerY: 0.84,
            width: 0.25,
            height: 0.24,
        ),
    ],
)
let fusedDecision = planner.decide(grid: fused)
expect(fusedDecision.command == .stop, "high-confidence center detection should force stop")
expect(fusedDecision.reason == "near_obstacle", "high-confidence center detection should look like near obstacle")

var spokenMessages = [String]()
var nextUtterance = 1
let feedbackDispatcher = CorridorFeedbackDispatcher(
    speaker: { message, _, utteranceId in
        spokenMessages.append("\(message):\(utteranceId)")
    },
    utteranceIdFactory: {
        defer { nextUtterance += 1 }
        return "utterance-\(nextUtterance)"
    },
)
let initialStop = feedbackDispatcher.dispatch(
    state: CorridorState(
        command: .stop,
        sourceDecision: CorridorDecision(command: .stop, path: [], reason: "near_obstacle"),
        pendingCommand: nil,
        pendingCount: 0,
        changed: false,
    ),
)
expect(initialStop.spoken, "initial emergency stop should speak")
expect(initialStop.messageKey == "stop", "initial emergency stop message key")
let repeatedStop = feedbackDispatcher.dispatch(
    state: CorridorState(
        command: .stop,
        sourceDecision: CorridorDecision(command: .stop, path: [], reason: "near_obstacle"),
        pendingCommand: nil,
        pendingCount: 0,
        changed: false,
    ),
)
expect(!repeatedStop.spoken, "repeated unchanged stop should not speak")
expect(spokenMessages == ["Stop:utterance-1"], "only first emergency stop should speak")

let pipelineSpoken = CorridorPipeline(
    stateMachine: CorridorStateMachine(confirmationsRequired: 1),
    feedbackDispatcher: CorridorFeedbackDispatcher(
        speaker: { message, _, _ in spokenMessages.append(message) },
        utteranceIdFactory: { "pipeline-utterance" },
    ),
).process(grid: grid())
expect(pipelineSpoken.feedbackEvent?.messageKey == "go_straight", "pipeline should dispatch go_straight")

print("CorridorCoreSmoke passed")
