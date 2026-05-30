// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import AVFoundation
import Foundation

final class SpeechFeedbackDispatcher {
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenLabel: String?
    private var lastSpeechTime = Date.distantPast
    private let minimumRepeatInterval: TimeInterval = 4.0

    func speak(detection: YoloObstacleDetector.Detection) {
        DispatchQueue.main.async { [weak self] in
            self?.speakOnMain(detection: detection)
        }
    }

    private func speakOnMain(detection: YoloObstacleDetector.Detection) {
        let now = Date()
        guard shouldSpeak(label: detection.label, now: now) else {
            print(
                "roana_ios_speech status=suppressed label=\(sanitizeSpeechLogValue(detection.label)) " +
                    "score=\(detection.scorePercent)",
            )
            return
        }

        let message = message(for: detection)
        let utterance = AVSpeechUtterance(string: message)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier) ??
            AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)

        lastSpokenLabel = detection.label
        lastSpeechTime = now
        print(
            "roana_ios_speech status=queued label=\(sanitizeSpeechLogValue(detection.label)) " +
                "score=\(detection.scorePercent) message=\(sanitizeSpeechLogValue(message))",
        )
    }

    private func shouldSpeak(label: String, now: Date) -> Bool {
        label != lastSpokenLabel || now.timeIntervalSince(lastSpeechTime) >= minimumRepeatInterval
    }

    private func message(for detection: YoloObstacleDetector.Detection) -> String {
        switch detection.label {
        case "person":
            "Person ahead"
        default:
            "\(detection.label) ahead"
        }
    }
}

private func sanitizeSpeechLogValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: " ", with: "_")
        .replacingOccurrences(of: "\n", with: "_")
}
