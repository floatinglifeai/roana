// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

func fail(_ message: String) -> Never {
    fputs("YoloSpeechSmoke failed: \(message)\n", stderr)
    exit(1)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

let policy = YoloSpeechFeedbackPolicy(minimumRepeatInterval: 4.0)
let started = Date(timeIntervalSince1970: 10.0)
let person = YoloSpeechDetection(label: "person", scorePercent: 91)
let chair = YoloSpeechDetection(label: "chair", scorePercent: 77)

let first = policy.feedback(for: person, now: started)
expect(first?.message == "Person ahead", "first person detection should speak")
expect(first?.detection == person, "first feedback should preserve detection")

let unmarkedRetry = policy.feedback(for: person, now: started.addingTimeInterval(1.0))
expect(unmarkedRetry?.message == "Person ahead", "unmarked feedback should not throttle retries")

guard let first else {
    fail("first feedback missing")
}
policy.markSpoken(first, at: started)

let repeated = policy.feedback(for: person, now: started.addingTimeInterval(1.0))
expect(repeated == nil, "same label inside repeat interval should be suppressed")

let different = policy.feedback(for: chair, now: started.addingTimeInterval(2.0))
expect(different?.message == "chair ahead", "different label should speak immediately")
expect(different?.detection == chair, "different feedback should preserve detection")

let repeatAfterInterval = policy.feedback(for: chair, now: started.addingTimeInterval(6.1))
expect(repeatAfterInterval?.message == "chair ahead", "same label after repeat interval should speak")

let consumePolicy = YoloSpeechFeedbackPolicy(minimumRepeatInterval: 4.0)
let consumed = consumePolicy.consumeFeedback(for: person, now: started)
expect(consumed?.message == "Person ahead", "consumeFeedback should return first feedback")
let consumedRepeat = consumePolicy.consumeFeedback(for: person, now: started.addingTimeInterval(1.0))
expect(consumedRepeat == nil, "consumeFeedback should mark spoken feedback")

print("YoloSpeechSmoke passed")
