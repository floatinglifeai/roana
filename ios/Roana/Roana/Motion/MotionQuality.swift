// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

enum MotionQualityLabel: String {
    case stable
    case pointingDown = "pointing_down"
    case unstable
}

struct MotionQuality: Equatable {
    let label: MotionQualityLabel
    let reason: String

    var trustsGuidance: Bool {
        label == .stable
    }
}

struct MotionQualitySample: Equatable {
    let pitchDegrees: Double
    let angularVelocityDegreesPerSecond: Double

    init(pitchDegrees: Double, angularVelocityDegreesPerSecond: Double) {
        self.pitchDegrees = pitchDegrees
        self.angularVelocityDegreesPerSecond = angularVelocityDegreesPerSecond
    }
}

enum MotionQualityClassifier {
    static let pointingDownPitchDegrees = -55.0
    static let unstableAngularVelocityDegreesPerSecond = 120.0

    static func classify(_ sample: MotionQualitySample?) -> MotionQuality {
        guard let sample else {
            return MotionQuality(label: .stable, reason: "motion_unavailable")
        }

        if sample.pitchDegrees <= pointingDownPitchDegrees {
            return MotionQuality(label: .pointingDown, reason: "pitch_down")
        }

        if abs(sample.angularVelocityDegreesPerSecond) >= unstableAngularVelocityDegreesPerSecond {
            return MotionQuality(label: .unstable, reason: "high_angular_velocity")
        }

        return MotionQuality(label: .stable, reason: "motion_stable")
    }
}
