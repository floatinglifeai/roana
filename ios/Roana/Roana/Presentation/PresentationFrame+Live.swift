// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

/// Bridges the live corridor / detection types to the dependency-free
/// PresentationFrame. Kept separate so PresentationContract.swift stays pure.
extension PresentationFrame {
    static func from(
        grid: DepthGrid,
        detections: [YoloObstacleDetector.Detection],
        state: CorridorState,
        frames: Int,
        yoloMs: Double,
        depthMs: Double,
        gaps: Int
    ) -> PresentationFrame {
        PresentationFrame(
            command: roanaCommand(state.command),
            reason: state.sourceDecision.reason,
            depth: grid.toFloatArray(),
            depthCols: grid.cols,
            detections: detections.map {
                DetectionBox(label: $0.label, score: $0.confidence,
                             centerX: $0.centerX, centerY: $0.centerY,
                             width: $0.width, height: $0.height)
            },
            frames: frames, yoloMs: yoloMs, depthMs: depthMs, gaps: gaps)
    }

    static func roanaCommand(_ c: CorridorCommand) -> RoanaCommand {
        switch c {
        case .straight: return .straight
        case .left: return .left
        case .right: return .right
        case .stop: return .stop
        }
    }
}
