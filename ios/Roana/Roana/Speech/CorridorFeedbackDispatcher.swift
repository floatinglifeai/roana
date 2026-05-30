// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import AVFoundation
import Foundation

final class CorridorFeedbackDispatcher {
    struct Event: Equatable {
        let command: CorridorCommand
        let messageKey: String
        let reason: String
        let changed: Bool
        let forced: Bool
        let spoken: Bool
        let utteranceId: String?
        let pendingCommand: CorridorCommand?
        let pendingCount: Int
    }

    enum QueueMode {
        case flush
    }

    typealias Speaker = (_ message: String, _ queueMode: QueueMode, _ utteranceId: String) -> Void

    private let speaker: Speaker
    private let utteranceIdFactory: () -> String
    private var hasSpoken = false

    init(
        speaker: @escaping Speaker,
        utteranceIdFactory: @escaping () -> String,
    ) {
        self.speaker = speaker
        self.utteranceIdFactory = utteranceIdFactory
    }

    convenience init(synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer()) {
        self.init(
            speaker: { message, _, utteranceId in
                DispatchQueue.main.async {
                    guard SpeechAudioSession.activate() else {
                        print(
                            "roana_ios_corridor_feedback_audio status=suppressed " +
                                "reason=audio_session_failed id=\(utteranceId)",
                        )
                        return
                    }

                    let utterance = AVSpeechUtterance(string: message)
                    utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier) ??
                        AVSpeechSynthesisVoice(language: "en-US")
                    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
                    synthesizer.stopSpeaking(at: .immediate)
                    synthesizer.speak(utterance)
                    print(
                        "roana_ios_corridor_feedback_audio status=queued " +
                            "id=\(utteranceId) message=\(sanitizeCorridorFeedbackValue(message))",
                    )
                }
            },
            utteranceIdFactory: {
                "roana-ios-corridor-\(Int(Date().timeIntervalSince1970 * 1_000))"
            },
        )
    }

    func dispatch(state: CorridorState, force: Bool = false) -> Event {
        let feedback = feedbackFor(command: state.command)
        let shouldSpeak = force || state.changed || (!hasSpoken && state.requiresInitialStopFeedback)
        let utteranceId = shouldSpeak ? utteranceIdFactory() : nil

        if shouldSpeak, let utteranceId {
            speaker(feedback.message, .flush, utteranceId)
            hasSpoken = true
        }

        let event = Event(
            command: state.command,
            messageKey: feedback.messageKey,
            reason: state.sourceDecision.reason,
            changed: state.changed,
            forced: force,
            spoken: shouldSpeak,
            utteranceId: utteranceId,
            pendingCommand: state.pendingCommand,
            pendingCount: state.pendingCount,
        )
        log(event)
        return event
    }

    private func feedbackFor(command: CorridorCommand) -> CommandFeedback {
        switch command {
        case .left:
            CommandFeedback(message: "Turn left", messageKey: "turn_left")
        case .straight:
            CommandFeedback(message: "Go straight", messageKey: "go_straight")
        case .right:
            CommandFeedback(message: "Turn right", messageKey: "turn_right")
        case .stop:
            CommandFeedback(message: "Stop", messageKey: "stop")
        }
    }

    private func log(_ event: Event) {
        print(
            "roana_ios_corridor_feedback status=\(event.spoken ? "spoken" : "suppressed") " +
                "id=\(event.utteranceId ?? "none") command=\(event.command.rawValue) " +
                "message=\(event.messageKey) reason=\(event.reason) changed=\(event.changed) " +
                "forced=\(event.forced) pending=\(event.pendingCommand?.rawValue ?? "none") " +
                "pending_count=\(event.pendingCount)",
        )
    }
}

private struct CommandFeedback {
    let message: String
    let messageKey: String
}

private extension CorridorState {
    var requiresInitialStopFeedback: Bool {
        command == .stop &&
            (
                sourceDecision.command == .stop ||
                    sourceDecision.reason == "frame_loss" ||
                    sourceDecision.reason == "low_confidence"
            )
    }
}

private func sanitizeCorridorFeedbackValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: " ", with: "_")
        .replacingOccurrences(of: "\n", with: "_")
}
