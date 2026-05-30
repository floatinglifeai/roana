// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

struct YoloSpeechDetection: Equatable {
    let label: String
    let scorePercent: Int
}

struct YoloSpeechFeedback: Equatable {
    let detection: YoloSpeechDetection
    let message: String
}

final class YoloSpeechFeedbackPolicy {
    private var lastSpokenLabel: String?
    private var lastSpeechTime = Date.distantPast
    private let minimumRepeatInterval: TimeInterval

    init(minimumRepeatInterval: TimeInterval = 4.0) {
        self.minimumRepeatInterval = minimumRepeatInterval
    }

    func feedback(for detection: YoloSpeechDetection, now: Date) -> YoloSpeechFeedback? {
        guard shouldSpeak(label: detection.label, now: now) else {
            return nil
        }
        return YoloSpeechFeedback(
            detection: detection,
            message: message(for: detection.label),
        )
    }

    func markSpoken(_ feedback: YoloSpeechFeedback, at now: Date) {
        lastSpokenLabel = feedback.detection.label
        lastSpeechTime = now
    }

    func consumeFeedback(for detection: YoloSpeechDetection, now: Date) -> YoloSpeechFeedback? {
        guard let feedback = feedback(for: detection, now: now) else {
            return nil
        }
        markSpoken(feedback, at: now)
        return feedback
    }

    func shouldSpeak(label: String, now: Date) -> Bool {
        label != lastSpokenLabel || now.timeIntervalSince(lastSpeechTime) >= minimumRepeatInterval
    }

    private func message(for label: String) -> String {
        switch label {
        case "person":
            "Person ahead"
        default:
            "\(label) ahead"
        }
    }
}
