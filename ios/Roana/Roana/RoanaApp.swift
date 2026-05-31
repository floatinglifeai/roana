// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import SwiftUI

@main
struct RoanaApp: App {
    var body: some Scene {
        WindowGroup {
            rootView
        }
    }

    @ViewBuilder private var rootView: some View {
        #if DEBUG
            if let replayOptions = VideoReplayBenchmarkOptions.current() {
                VideoReplayBenchmarkView(options: replayOptions)
            } else {
                CameraRootView()
            }
        #else
            CameraRootView()
        #endif
    }
}
