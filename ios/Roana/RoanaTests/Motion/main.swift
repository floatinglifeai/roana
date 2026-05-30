// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

func fail(_ message: String) -> Never {
    fputs("MotionQualitySmoke failed: \(message)\n", stderr)
    exit(1)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

let stable = MotionQualityClassifier.classify(
    MotionQualitySample(pitchDegrees: -10, angularVelocityDegreesPerSecond: 20),
)
expect(stable.label == .stable, "stable sample should be stable")
expect(stable.reason == "motion_stable", "stable reason should be motion_stable")
expect(stable.trustsGuidance, "stable sample should trust guidance")

let missing = MotionQualityClassifier.classify(nil)
expect(missing.label == .stable, "missing motion should not block image-only guidance")
expect(missing.reason == "motion_unavailable", "missing motion reason")
expect(missing.trustsGuidance, "missing motion keeps image-only behavior available")

let pointingDown = MotionQualityClassifier.classify(
    MotionQualitySample(pitchDegrees: -60, angularVelocityDegreesPerSecond: 10),
)
expect(pointingDown.label == .pointingDown, "low pitch should be pointing_down")
expect(pointingDown.reason == "pitch_down", "pointing_down reason")
expect(!pointingDown.trustsGuidance, "pointing_down should not trust guidance")

let unstable = MotionQualityClassifier.classify(
    MotionQualitySample(pitchDegrees: -20, angularVelocityDegreesPerSecond: 130),
)
expect(unstable.label == .unstable, "fast angular velocity should be unstable")
expect(unstable.reason == "high_angular_velocity", "unstable reason")
expect(!unstable.trustsGuidance, "unstable should not trust guidance")

let negativeUnstable = MotionQualityClassifier.classify(
    MotionQualitySample(pitchDegrees: -20, angularVelocityDegreesPerSecond: -130),
)
expect(negativeUnstable.label == .unstable, "negative angular velocity magnitude should be unstable")

print("MotionQualitySmoke passed")
