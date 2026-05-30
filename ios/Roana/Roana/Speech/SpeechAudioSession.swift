// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation

#if os(iOS)
    import AVFoundation
#endif

enum SpeechAudioSession {
    static func activate() -> Bool {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers],
            )
            try session.setActive(true, options: [])
            print("roana_ios_audio_session status=active category=playback mode=spokenAudio options=duckOthers")
            return true
        } catch {
            print("roana_ios_audio_session status=failed error=\(sanitizeAudioSessionValue(error.localizedDescription))")
            return false
        }
        #else
            print("roana_ios_audio_session status=active category=portable_smoke mode=spokenAudio options=duckOthers")
            return true
        #endif
    }
}

private func sanitizeAudioSessionValue(_ value: String) -> String {
    value
        .replacingOccurrences(of: " ", with: "_")
        .replacingOccurrences(of: "\n", with: "_")
}
