// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import AVFoundation
import Foundation

final class SpeechFeedbackDispatcher {
    private let synthesizer = AVSpeechSynthesizer()
    private let feedbackPolicy = YoloSpeechFeedbackPolicy()

    func speak(detection: YoloObstacleDetector.Detection) {
        DispatchQueue.main.async { [weak self] in
            self?.speakOnMain(detection: detection)
        }
    }

    func suppress(detection: YoloObstacleDetector.Detection, reason: String) {
        print(
            "roana_ios_speech status=suppressed reason=\(sanitizeSpeechLogValue(reason)) " +
                "label=\(sanitizeSpeechLogValue(detection.label)) score=\(detection.scorePercent)",
        )
    }

    private func speakOnMain(detection: YoloObstacleDetector.Detection) {
        let now = Date()
        let speechDetection = YoloSpeechDetection(
            label: detection.label,
            scorePercent: detection.scorePercent,
        )
        guard let feedback = feedbackPolicy.feedback(for: speechDetection, now: now) else {
            print(
                "roana_ios_speech status=suppressed reason=repeat_interval " +
                    "label=\(sanitizeSpeechLogValue(detection.label)) score=\(detection.scorePercent)",
            )
            return
        }

        guard SpeechAudioSession.activate() else {
            print(
                "roana_ios_speech status=suppressed reason=audio_session_failed " +
                    "label=\(sanitizeSpeechLogValue(detection.label)) score=\(detection.scorePercent)",
            )
            return
        }

        let utterance = AVSpeechUtterance(string: feedback.message)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier) ??
            AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)

        print(
            "roana_ios_speech status=queued label=\(sanitizeSpeechLogValue(detection.label)) " +
                "score=\(detection.scorePercent) message=\(sanitizeSpeechLogValue(feedback.message))",
        )
    }
}

private func sanitizeSpeechLogValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: " ", with: "_")
        .replacingOccurrences(of: "\n", with: "_")
}
