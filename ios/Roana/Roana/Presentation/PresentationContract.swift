// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import SwiftUI

/// iOS mirror of parity/presentation-core.json. Keep in sync with the JSON and
/// with Android's RoanaPresentation.kt; the presentation parity test catches drift.
/// Depth thresholds come from the shared corridor constants, not re-declared here.
enum RoanaCommand {
    case straight, left, right, stop
}

struct CommandStyle {
    let glyph: String
    let color: Color
    let caption: String
    let pathTargetCol: Int
}

enum RoanaPresentation {
    static let grid = 15            // == CorridorContract.gridSize

    static func style(_ command: RoanaCommand) -> CommandStyle {
        switch command {
        case .straight: return CommandStyle(glyph: "↑", color: hex(0x62E08A), caption: "Go straight", pathTargetCol: 7)
        case .left:     return CommandStyle(glyph: "←", color: hex(0x5CC8FF), caption: "Turn left",   pathTargetCol: 4)
        case .right:    return CommandStyle(glyph: "→", color: hex(0xC89BFF), caption: "Turn right",  pathTargetCol: 10)
        case .stop:     return CommandStyle(glyph: "■", color: hex(0xFF5563), caption: "Stop",        pathTargetCol: 7)
        }
    }

    static let detectionStroke = hex(0x3AD6C0)
    static let hudBackground = hex(0x06080C)
    static let ambientBackground = hex(0x03050A)
    static let stopEdge = hex(0xFF5563)

    static let gestureRegion: CGFloat = 88
    static let gestureHold: TimeInterval = 2.0

    // Far -> near = cool -> warm; stops sit on the corridor thresholds (0.72 / 0.86).
    private static let ramp: [(Float, (Double, Double, Double))] = [
        (0.00, (8, 24, 58)),
        (0.35, (12, 92, 120)),
        (0.55, (24, 150, 120)),
        (0.72, (180, 190, 60)),
        (0.86, (230, 140, 40)),
        (1.00, (220, 50, 50)),
    ]

    static func depthColor(_ value: Float) -> Color {
        let v = min(max(value, 0), 1)
        for i in 0 ..< ramp.count - 1 {
            let (a, ca) = ramp[i]
            let (b, cb) = ramp[i + 1]
            if v >= a && v <= b {
                let f = Double(b == a ? 0 : (v - a) / (b - a))
                return Color(.sRGB,
                             red: (ca.0 + (cb.0 - ca.0) * f) / 255,
                             green: (ca.1 + (cb.1 - ca.1) * f) / 255,
                             blue: (ca.2 + (cb.2 - ca.2) * f) / 255)
            }
        }
        let last = ramp.last!.1
        return Color(.sRGB, red: last.0 / 255, green: last.1 / 255, blue: last.2 / 255)
    }

    static func hex(_ v: UInt32) -> Color {
        Color(.sRGB,
              red: Double((v >> 16) & 0xFF) / 255,
              green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255)
    }
}

/// Normalized obstacle box (0..1).
struct DetectionBox {
    let label: String
    let score: Float
    let centerX: Float
    let centerY: Float
    let width: Float
    let height: Float
}

/// Everything an overlay needs for one frame. Built at the inference site and
/// published from CameraSessionController.
struct PresentationFrame {
    var command: RoanaCommand = .stop
    var reason: String = "no_safe_corridor"
    var depth: [Float] = Array(repeating: 0.2, count: 15 * 15)
    var depthCols: Int = 15
    var detections: [DetectionBox] = []
    var frames: Int = 0
    var yoloMs: Double = 0
    var depthMs: Double = 0
    var gaps: Int = 0

    func depthAt(_ row: Int, _ col: Int) -> Float { depth[row * depthCols + col] }

    var telemetry: [(String, String)] {
        [("FRM", "\(frames)"),
         ("YOLO ms", "\(Int(yoloMs))"),
         ("DEPTH ms", "\(Int(depthMs))"),
         ("GAPS", "\(gaps)")]
    }
}
