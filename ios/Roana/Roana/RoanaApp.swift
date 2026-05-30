// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import SwiftUI

@main
struct RoanaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = CameraSessionController()

    var body: some Scene {
        WindowGroup {
            ContentView(camera: camera)
        }
        .onChange(of: scenePhase) { _, newPhase in
            camera.handleScenePhase(newPhase)
        }
    }
}
