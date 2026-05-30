// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

final class CorridorPlanner {
    func decide(grid: DepthGrid) -> CorridorDecision {
        precondition(
            grid.rows == CorridorConstants.gridSize && grid.cols == CorridorConstants.gridSize,
            "Expected \(CorridorConstants.gridSize)x\(CorridorConstants.gridSize) depth grid, got \(grid.rows)x\(grid.cols)",
        )

        if grid.nearestBottomCenter() >= CorridorConstants.nearObstacleDepth {
            return CorridorDecision(command: .stop, path: [], reason: "near_obstacle")
        }

        let start = Cell(row: CorridorConstants.gridSize - 1, col: CorridorConstants.gridSize / 2)
        let path = search(grid: grid, start: start)
        if path.count < CorridorConstants.minimumPathCells {
            return CorridorDecision(command: .stop, path: path, reason: "no_safe_corridor")
        }

        let endpoint = path[path.count - 1]
        let offset = endpoint.col - start.col
        let command: CorridorCommand
        if offset <= -CorridorConstants.turnOffsetCells {
            command = .left
        } else if offset >= CorridorConstants.turnOffsetCells {
            command = .right
        } else {
            command = .straight
        }

        return CorridorDecision(command: command, path: path, reason: "path_found")
    }

    private func search(grid: DepthGrid, start: Cell) -> [Cell] {
        var memo = Array<PathCandidate?>(repeating: nil, count: CorridorConstants.gridSize * CorridorConstants.gridSize)
        return bestPathFrom(
            grid: grid,
            current: start,
            startCol: start.col,
            memo: &memo,
        ).toCells()
    }

    private func bestPathFrom(
        grid: DepthGrid,
        current: Cell,
        startCol: Int,
        memo: inout [PathCandidate?],
    ) -> PathCandidate {
        let memoIndex = current.row * CorridorConstants.gridSize + current.col
        if let cached = memo[memoIndex] {
            return cached
        }

        var bestNext: PathCandidate?
        if current.row > 0 {
            for candidate in nextCandidates(current: current) {
                if grid.contains(candidate),
                   grid[candidate] <= CorridorConstants.safeCellDepth,
                   grid[candidate] <= grid[current] + CorridorConstants.maximumForwardDepthRise {
                    let nextPath = bestPathFrom(
                        grid: grid,
                        current: candidate,
                        startCol: startCol,
                        memo: &memo,
                    )
                    if nextPath.isBetter(than: bestNext) {
                        bestNext = nextPath
                    }
                }
            }
        }

        let result = PathCandidate(
            cell: current,
            length: 1 + (bestNext?.length ?? 0),
            clearanceScore: horizontalClearance(grid: grid, cell: current) + (bestNext?.clearanceScore ?? 0),
            straightnessScore: -abs(current.col - startCol) + (bestNext?.straightnessScore ?? 0),
            next: bestNext,
        )
        memo[memoIndex] = result
        return result
    }

    private func nextCandidates(current: Cell) -> [Cell] {
        [
            Cell(row: current.row - 1, col: current.col),
            Cell(row: current.row - 1, col: current.col - 1),
            Cell(row: current.row - 1, col: current.col + 1),
        ]
    }

    private func horizontalClearance(grid: DepthGrid, cell: Cell) -> Int {
        if grid[cell] > CorridorConstants.safeCellDepth {
            return 0
        }

        var left = 0
        var col = cell.col - 1
        while col >= 0 && grid[Cell(row: cell.row, col: col)] <= CorridorConstants.safeCellDepth {
            left += 1
            col -= 1
        }

        var right = 0
        col = cell.col + 1
        while col < CorridorConstants.gridSize && grid[Cell(row: cell.row, col: col)] <= CorridorConstants.safeCellDepth {
            right += 1
            col += 1
        }

        return min(left, right)
    }
}

struct DepthGrid: Equatable {
    let rows: Int
    let cols: Int
    private let values: [Float]

    init(rows: Int, cols: Int, values: [Float]) {
        precondition(rows > 0 && cols > 0, "Depth grid dimensions must be positive")
        precondition(values.count == rows * cols, "Depth grid value count \(values.count) does not match \(rows)x\(cols)")
        self.rows = rows
        self.cols = cols
        self.values = values
    }

    subscript(cell: Cell) -> Float {
        values[cell.row * cols + cell.col]
    }

    func toFloatArray() -> [Float] {
        values
    }

    func contains(_ cell: Cell) -> Bool {
        (0..<rows).contains(cell.row) && (0..<cols).contains(cell.col)
    }

    func nearestBottomCenter() -> Float {
        var nearest = -Float.infinity
        let centerCol = cols / 2
        for row in (rows - CorridorConstants.imminentObstacleRows)..<rows {
            for col in (centerCol - CorridorConstants.imminentObstacleHalfWidth)...(centerCol + CorridorConstants.imminentObstacleHalfWidth) {
                nearest = max(nearest, values[row * cols + col])
            }
        }
        return nearest
    }

    static func square15(_ values: [Float]) -> DepthGrid {
        DepthGrid(rows: CorridorConstants.gridSize, cols: CorridorConstants.gridSize, values: values)
    }

    static func fromDepthMap(values: [Float], rows: Int, cols: Int) -> DepthGrid {
        precondition(rows > 0 && cols > 0, "Depth map dimensions must be positive")
        precondition(values.count == rows * cols, "Depth map value count \(values.count) does not match \(rows)x\(cols)")

        let minimum = values.min() ?? 0
        let maximum = values.max() ?? minimum
        let range = maximum - minimum
        var output = Array<Float>(repeating: 0, count: CorridorConstants.gridSize * CorridorConstants.gridSize)

        for gridRow in 0..<CorridorConstants.gridSize {
            let sourceRowStart = gridRow * rows / CorridorConstants.gridSize
            let sourceRowEnd = max(sourceRowStart + 1, (gridRow + 1) * rows / CorridorConstants.gridSize)
            for gridCol in 0..<CorridorConstants.gridSize {
                let sourceColStart = gridCol * cols / CorridorConstants.gridSize
                let sourceColEnd = max(sourceColStart + 1, (gridCol + 1) * cols / CorridorConstants.gridSize)
                var sum: Double = 0
                var count = 0
                for sourceRow in sourceRowStart..<sourceRowEnd {
                    for sourceCol in sourceColStart..<sourceColEnd {
                        sum += Double(values[sourceRow * cols + sourceCol])
                        count += 1
                    }
                }
                let average = Float(sum / Double(count))
                output[gridRow * CorridorConstants.gridSize + gridCol] = range > 0 ? (average - minimum) / range : 0
            }
        }

        return square15(output)
    }

    static func depthMapValues(values: [Float], rows: Int, cols: Int) -> [Float] {
        fromDepthMap(values: values, rows: rows, cols: cols).toFloatArray()
    }
}

struct Cell: Equatable {
    let row: Int
    let col: Int
}

struct CorridorDecision: Equatable {
    let command: CorridorCommand
    let path: [Cell]
    let reason: String
}

enum CorridorCommand: String, Equatable {
    case left = "LEFT"
    case straight = "STRAIGHT"
    case right = "RIGHT"
    case stop = "STOP"
}

private final class PathCandidate {
    let cell: Cell
    let length: Int
    let clearanceScore: Int
    let straightnessScore: Int
    let next: PathCandidate?

    init(
        cell: Cell,
        length: Int,
        clearanceScore: Int,
        straightnessScore: Int,
        next: PathCandidate?,
    ) {
        self.cell = cell
        self.length = length
        self.clearanceScore = clearanceScore
        self.straightnessScore = straightnessScore
        self.next = next
    }

    func isBetter(than other: PathCandidate?) -> Bool {
        guard let other else {
            return true
        }

        return length > other.length ||
            (length == other.length && clearanceScore > other.clearanceScore) ||
            (
                length == other.length &&
                    clearanceScore == other.clearanceScore &&
                    straightnessScore > other.straightnessScore
            )
    }

    func toCells() -> [Cell] {
        var cells = [Cell]()
        var current: PathCandidate? = self
        while let candidate = current {
            cells.append(candidate.cell)
            current = candidate.next
        }
        return cells
    }
}

enum CorridorConstants {
    static let gridSize = 15
    static let nearObstacleDepth: Float = 0.86
    static let safeCellDepth: Float = 0.72
    static let maximumForwardDepthRise: Float = 0.12
    static let minimumPathCells = 6
    static let turnOffsetCells = 3
    static let imminentObstacleRows = 3
    static let imminentObstacleHalfWidth = 1
}
