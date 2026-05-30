// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

struct Fixture: Decodable {
    let schema: Int
    let cases: [FixtureCase]
}

struct FixtureCase: Decodable {
    let name: String
    let type: String
    let confirmationsRequired: Int?
    let grid: GridFixture?
    let expected: ExpectedDecision?
    let expectedDepthGrid: ExpectedDepthGrid?
    let decisions: [DecisionFixture]?
    let expectedStates: [ExpectedState]?
    let detections: [DetectionFixture]?
    let depthOutput: DepthOutputFixture?
    let steps: [PipelineStep]?
    let feedbackStates: [FeedbackState]?
    let expectedEvents: [ExpectedFeedbackEvent]?
    let expectedSpoken: [ExpectedSpoken]?
}

struct GridFixture: Decodable {
    let kind: String
    let value: Float?
    let colsFromBottom: [Int]?
    let overrides: [GridOverride]?
}

struct GridOverride: Decodable {
    let row: Int
    let col: Int
    let value: Float
}

struct ExpectedDecision: Decodable {
    let command: String
    let reason: String
    let pathCells: Int?
    let minPathCells: Int?
}

struct DecisionFixture: Decodable {
    let command: String
    let reason: String
}

struct ExpectedState: Decodable {
    let command: String
    let changed: Bool
    let pendingCommand: String?
    let pendingCount: Int
}

struct PipelineStep: Decodable {
    let action: String
    let grid: GridFixture?
    let reason: String?
    let expectedDecision: ExpectedDecision
    let expectedState: ExpectedState
    let expectedFeedback: ExpectedFeedbackEvent?
}

struct FeedbackState: Decodable {
    let command: String
    let sourceCommand: String
    let reason: String
    let changed: Bool
    let pendingCommand: String?
    let pendingCount: Int
    let force: Bool
}

struct ExpectedFeedbackEvent: Decodable {
    let command: String
    let messageKey: String
    let reason: String
    let changed: Bool
    let forced: Bool
    let spoken: Bool
    let utteranceId: String?
    let pendingCommand: String?
    let pendingCount: Int
}

struct ExpectedSpoken: Decodable, Equatable {
    let message: String
    let queueMode: String
    let utteranceId: String
}

struct DetectionFixture: Decodable {
    let confidence: Float
    let centerX: Float
    let centerY: Float
    let width: Float
    let height: Float
}

struct DepthOutputFixture: Decodable {
    let rows: Int
    let cols: Int
    let pattern: String
}

struct ExpectedDepthGrid: Decodable {
    let rows: Int
    let cols: Int
    let sum: Float
    let min: Float
    let max: Float
    let probes: [DepthProbe]
}

struct DepthProbe: Decodable {
    let index: Int
    let value: Float
}

func fail(_ message: String) -> Never {
    fputs("CorridorParity failed: \(message)\n", stderr)
    exit(1)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

func expectClose(_ actual: Float, _ expected: Float, _ message: String) {
    if abs(actual - expected) > 0.0001 {
        fail("\(message): \(actual) != \(expected)")
    }
}

func command(_ rawValue: String) -> CorridorCommand {
    switch rawValue {
    case "LEFT":
        .left
    case "STRAIGHT":
        .straight
    case "RIGHT":
        .right
    case "STOP":
        .stop
    default:
        fail("unknown command \(rawValue)")
    }
}

func buildGrid(_ fixture: GridFixture, caseName: String) -> DepthGrid {
    var values: [Float]
    switch fixture.kind {
    case "filled":
        values = Array(
            repeating: fixture.value ?? 0,
            count: CorridorConstants.gridSize * CorridorConstants.gridSize,
        )
    case "carvedCorridor":
        values = Array(repeating: 0.95, count: CorridorConstants.gridSize * CorridorConstants.gridSize)
        guard let colsFromBottom = fixture.colsFromBottom else {
            fail("\(caseName): carvedCorridor missing colsFromBottom")
        }
        for (offset, col) in colsFromBottom.enumerated() {
            let row = CorridorConstants.gridSize - 1 - offset
            for safeCol in (col - 1)...(col + 1) where (0..<CorridorConstants.gridSize).contains(safeCol) {
                values[row * CorridorConstants.gridSize + safeCol] = 0.35 - Float(offset) * 0.02
            }
        }
    default:
        fail("\(caseName): unknown grid kind \(fixture.kind)")
    }

    for override in fixture.overrides ?? [] {
        values[override.row * CorridorConstants.gridSize + override.col] = override.value
    }

    return DepthGrid.square15(values)
}

func checkDecision(_ decision: CorridorDecision, expected: ExpectedDecision, caseName: String) {
    expect(decision.command.rawValue == expected.command, "\(caseName): command \(decision.command.rawValue) != \(expected.command)")
    expect(decision.reason == expected.reason, "\(caseName): reason \(decision.reason) != \(expected.reason)")
    if let pathCells = expected.pathCells {
        expect(decision.path.count == pathCells, "\(caseName): pathCells \(decision.path.count) != \(pathCells)")
    }
    if let minPathCells = expected.minPathCells {
        expect(decision.path.count >= minPathCells, "\(caseName): pathCells \(decision.path.count) < \(minPathCells)")
    }
}

func checkState(_ state: CorridorState, expected: ExpectedState, caseName: String) {
    expect(state.command.rawValue == expected.command, "\(caseName): state command \(state.command.rawValue) != \(expected.command)")
    expect(state.changed == expected.changed, "\(caseName): changed \(state.changed) != \(expected.changed)")
    expect(state.pendingCommand?.rawValue == expected.pendingCommand, "\(caseName): pending command mismatch")
    expect(state.pendingCount == expected.pendingCount, "\(caseName): pending count \(state.pendingCount) != \(expected.pendingCount)")
}

func checkFeedbackEvent(
    _ event: CorridorFeedbackDispatcher.Event?,
    expected: ExpectedFeedbackEvent?,
    caseName: String,
) {
    if expected == nil {
        expect(event == nil, "\(caseName): expected no feedback event")
        return
    }
    guard let event, let expected else {
        fail("\(caseName): feedback event presence mismatch")
    }
    expect(event.command.rawValue == expected.command, "\(caseName): feedback command mismatch")
    expect(event.messageKey == expected.messageKey, "\(caseName): feedback message mismatch")
    expect(event.reason == expected.reason, "\(caseName): feedback reason mismatch")
    expect(event.changed == expected.changed, "\(caseName): feedback changed mismatch")
    expect(event.forced == expected.forced, "\(caseName): feedback forced mismatch")
    expect(event.spoken == expected.spoken, "\(caseName): feedback spoken mismatch")
    expect(event.utteranceId == expected.utteranceId, "\(caseName): feedback utterance mismatch")
    expect(event.pendingCommand?.rawValue == expected.pendingCommand, "\(caseName): feedback pending command mismatch")
    expect(event.pendingCount == expected.pendingCount, "\(caseName): feedback pending count mismatch")
}

func checkPlannerCase(_ fixtureCase: FixtureCase) {
    guard let gridFixture = fixtureCase.grid, let expected = fixtureCase.expected else {
        fail("\(fixtureCase.name): planner case missing grid or expected")
    }
    let decision = CorridorPlanner().decide(grid: buildGrid(gridFixture, caseName: fixtureCase.name))
    checkDecision(decision, expected: expected, caseName: fixtureCase.name)
}

func checkFusionCase(_ fixtureCase: FixtureCase) {
    guard let gridFixture = fixtureCase.grid, let expected = fixtureCase.expected else {
        fail("\(fixtureCase.name): fusion case missing grid or expected")
    }
    let detections = (fixtureCase.detections ?? []).map {
        CorridorDetection(
            confidence: $0.confidence,
            centerX: $0.centerX,
            centerY: $0.centerY,
            width: $0.width,
            height: $0.height,
        )
    }
    let grid = CorridorGridFusion().fuse(
        depthGrid: buildGrid(gridFixture, caseName: fixtureCase.name),
        detections: detections,
    )
    let decision = CorridorPlanner().decide(grid: grid)
    checkDecision(decision, expected: expected, caseName: fixtureCase.name)
}

func checkDepthGridCase(_ fixtureCase: FixtureCase) {
    guard let depthOutput = fixtureCase.depthOutput,
          let expected = fixtureCase.expectedDepthGrid
    else {
        fail("\(fixtureCase.name): depthGrid case missing depth output or expected")
    }
    let values = depthValues(depthOutput)
    let grid = DepthAnythingOutputAdapter.plannerGrid(
        values: values,
        rows: depthOutput.rows,
        cols: depthOutput.cols,
    )
    let gridValues = grid.toFloatArray()
    expect(grid.rows == expected.rows, "\(fixtureCase.name): row count mismatch")
    expect(grid.cols == expected.cols, "\(fixtureCase.name): col count mismatch")
    expectClose(gridValues.reduce(0, +), expected.sum, "\(fixtureCase.name): sum mismatch")
    expectClose(gridValues.min() ?? 0, expected.min, "\(fixtureCase.name): min mismatch")
    expectClose(gridValues.max() ?? 0, expected.max, "\(fixtureCase.name): max mismatch")
    for probe in expected.probes {
        expectClose(gridValues[probe.index], probe.value, "\(fixtureCase.name): probe \(probe.index)")
    }
}

func checkStateMachineCase(_ fixtureCase: FixtureCase) {
    guard let decisions = fixtureCase.decisions, let expectedStates = fixtureCase.expectedStates else {
        fail("\(fixtureCase.name): stateMachine case missing decisions or expectedStates")
    }
    expect(decisions.count == expectedStates.count, "\(fixtureCase.name): state count mismatch")
    let stateMachine = CorridorStateMachine(confirmationsRequired: 3)
    for (index, decisionFixture) in decisions.enumerated() {
        let state = stateMachine.update(
            decision: CorridorDecision(
                command: command(decisionFixture.command),
                path: [],
                reason: decisionFixture.reason,
            ),
        )
        let expected = expectedStates[index]
        checkState(state, expected: expected, caseName: "\(fixtureCase.name)[\(index)]")
    }
}

func checkPipelineCase(_ fixtureCase: FixtureCase) {
    guard let steps = fixtureCase.steps else {
        fail("\(fixtureCase.name): pipeline case missing steps")
    }
    var spoken = [ExpectedSpoken]()
    var nextUtterance = 1
    let feedbackDispatcher: CorridorFeedbackDispatcher?
    if fixtureCase.expectedSpoken != nil || steps.contains(where: { $0.expectedFeedback != nil }) {
        feedbackDispatcher = CorridorFeedbackDispatcher(
            speaker: { message, queueMode, utteranceId in
                let mode: String
                switch queueMode {
                case .flush:
                    mode = "FLUSH"
                }
                spoken.append(ExpectedSpoken(message: message, queueMode: mode, utteranceId: utteranceId))
            },
            utteranceIdFactory: {
                defer { nextUtterance += 1 }
                return "utterance-\(nextUtterance)"
            },
        )
    } else {
        feedbackDispatcher = nil
    }
    let pipeline = CorridorPipeline(
        stateMachine: CorridorStateMachine(
            confirmationsRequired: fixtureCase.confirmationsRequired ?? 3,
        ),
        feedbackDispatcher: feedbackDispatcher,
    )

    for (index, step) in steps.enumerated() {
        let result: CorridorFrameResult
        switch step.action {
        case "process":
            guard let grid = step.grid else {
                fail("\(fixtureCase.name)[\(index)]: process step missing grid")
            }
            result = pipeline.process(grid: buildGrid(grid, caseName: fixtureCase.name))
        case "failSafeStop":
            result = pipeline.failSafeStop(reason: step.reason ?? "unknown")
        default:
            fail("\(fixtureCase.name)[\(index)]: unknown pipeline action \(step.action)")
        }
        checkDecision(result.decision, expected: step.expectedDecision, caseName: "\(fixtureCase.name)[\(index)]")
        checkState(result.state, expected: step.expectedState, caseName: "\(fixtureCase.name)[\(index)]")
        checkFeedbackEvent(result.feedbackEvent, expected: step.expectedFeedback, caseName: "\(fixtureCase.name)[\(index)]")
    }

    if let expectedSpoken = fixtureCase.expectedSpoken {
        expect(spoken == expectedSpoken, "\(fixtureCase.name): spoken feedback mismatch")
    }
}

func checkFeedbackCase(_ fixtureCase: FixtureCase) {
    guard let feedbackStates = fixtureCase.feedbackStates,
          let expectedEvents = fixtureCase.expectedEvents
    else {
        fail("\(fixtureCase.name): feedback case missing states or expected events")
    }
    expect(feedbackStates.count == expectedEvents.count, "\(fixtureCase.name): feedback event count mismatch")
    var spoken = [ExpectedSpoken]()
    var nextUtterance = 1
    let dispatcher = CorridorFeedbackDispatcher(
        speaker: { message, queueMode, utteranceId in
            let mode: String
            switch queueMode {
            case .flush:
                mode = "FLUSH"
            }
            spoken.append(ExpectedSpoken(message: message, queueMode: mode, utteranceId: utteranceId))
        },
        utteranceIdFactory: {
            defer { nextUtterance += 1 }
            return "utterance-\(nextUtterance)"
        },
    )

    for (index, feedbackState) in feedbackStates.enumerated() {
        let event = dispatcher.dispatch(
            state: CorridorState(
                command: command(feedbackState.command),
                sourceDecision: CorridorDecision(
                    command: command(feedbackState.sourceCommand),
                    path: [],
                    reason: feedbackState.reason,
                ),
                pendingCommand: feedbackState.pendingCommand.map(command),
                pendingCount: feedbackState.pendingCount,
                changed: feedbackState.changed,
            ),
            force: feedbackState.force,
        )
        checkFeedbackEvent(event, expected: expectedEvents[index], caseName: "\(fixtureCase.name)[\(index)]")
    }

    if let expectedSpoken = fixtureCase.expectedSpoken {
        expect(spoken == expectedSpoken, "\(fixtureCase.name): spoken feedback mismatch")
    }
}

func depthValues(_ fixture: DepthOutputFixture) -> [Float] {
    (0..<(fixture.rows * fixture.cols)).map { index in
        let row = index / fixture.cols
        let col = index % fixture.cols
        switch fixture.pattern {
        case "small2x2":
            return [0.1, 0.2, 0.3, 0.4][index]
        case "ramp":
            return Float(row * fixture.cols + col)
        case "constant":
            return 4.2
        default:
            fail("unknown depth pattern \(fixture.pattern)")
        }
    }
}

let arguments = CommandLine.arguments
let fixturePath = arguments.dropFirst().first ?? "parity/corridor-core.json"
let fixtureURL = URL(fileURLWithPath: fixturePath)
let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtureURL))
expect(fixture.schema == 1, "unsupported schema \(fixture.schema)")

for fixtureCase in fixture.cases {
    switch fixtureCase.type {
    case "planner":
        checkPlannerCase(fixtureCase)
    case "fusion":
        checkFusionCase(fixtureCase)
    case "depthGrid":
        checkDepthGridCase(fixtureCase)
    case "stateMachine":
        checkStateMachineCase(fixtureCase)
    case "pipeline":
        checkPipelineCase(fixtureCase)
    case "feedback":
        checkFeedbackCase(fixtureCase)
    default:
        fail("\(fixtureCase.name): unknown type \(fixtureCase.type)")
    }
}

print("CorridorParity passed cases=\(fixture.cases.count)")
