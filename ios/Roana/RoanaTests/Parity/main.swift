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
    let grid: GridFixture?
    let expected: ExpectedDecision?
    let decisions: [DecisionFixture]?
    let expectedStates: [ExpectedState]?
    let detections: [DetectionFixture]?
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

struct DetectionFixture: Decodable {
    let confidence: Float
    let centerX: Float
    let centerY: Float
    let width: Float
    let height: Float
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
        expect(state.command.rawValue == expected.command, "\(fixtureCase.name)[\(index)]: command mismatch")
        expect(state.changed == expected.changed, "\(fixtureCase.name)[\(index)]: changed mismatch")
        expect(state.pendingCommand?.rawValue == expected.pendingCommand, "\(fixtureCase.name)[\(index)]: pending command mismatch")
        expect(state.pendingCount == expected.pendingCount, "\(fixtureCase.name)[\(index)]: pending count mismatch")
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
    case "stateMachine":
        checkStateMachineCase(fixtureCase)
    default:
        fail("\(fixtureCase.name): unknown type \(fixtureCase.type)")
    }
}

print("CorridorParity passed cases=\(fixture.cases.count)")
