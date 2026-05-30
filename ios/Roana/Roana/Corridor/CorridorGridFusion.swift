// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

final class CorridorGridFusion {
    func fuse(
        depthGrid: DepthGrid,
        detections: [CorridorDetection],
    ) -> DepthGrid {
        var values = depthGrid.toFloatArray()
        detections
            .filter { $0.confidence >= CorridorConstants.detectionGridThreshold }
            .forEach { markDetection(grid: &values, detection: $0) }
        return DepthGrid.square15(values)
    }

    private func markDetection(
        grid: inout [Float],
        detection: CorridorDetection,
    ) {
        let left = clampToGrid(Int((detection.centerX - detection.width / 2) * Float(CorridorConstants.gridSize)))
        let right = clampToGrid(Int((detection.centerX + detection.width / 2) * Float(CorridorConstants.gridSize)))
        let top = clampToGrid(Int((detection.centerY - detection.height / 2) * Float(CorridorConstants.gridSize)))
        let bottom = clampToGrid(Int((detection.centerY + detection.height / 2) * Float(CorridorConstants.gridSize)))

        for row in top...bottom {
            for col in left...right {
                grid[row * CorridorConstants.gridSize + col] = CorridorConstants.detectionObstacleDepth
            }
        }
    }

    private func clampToGrid(_ value: Int) -> Int {
        min(max(value, 0), CorridorConstants.gridSize - 1)
    }
}

struct CorridorDetection: Equatable {
    let confidence: Float
    let centerX: Float
    let centerY: Float
    let width: Float
    let height: Float
}

private extension CorridorConstants {
    static let detectionGridThreshold: Float = 0.35
    static let detectionObstacleDepth: Float = 0.96
}
