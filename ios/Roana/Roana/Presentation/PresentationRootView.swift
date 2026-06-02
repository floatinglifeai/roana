// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import SwiftUI

/// Switches between the ambient (default) and debug surfaces. A 2s long-press in
/// the bottom-right corner toggles them. Mode is NOT persisted; every launch
/// starts in ambient. Mirrors Android's RoanaPresentationView.
struct PresentationRootView: View {
    let frame: PresentationFrame
    @State private var debug = false

    var body: some View {
        ZStack {
            if debug {
                DebugHudView(frame: frame)
            } else {
                AmbientView(command: frame.command)
            }

            // bottom-right corner long-press hotspot
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: RoanaPresentation.gestureRegion, height: RoanaPresentation.gestureRegion)
                    .position(x: geo.size.width - RoanaPresentation.gestureRegion / 2,
                              y: geo.size.height - RoanaPresentation.gestureRegion / 2)
                    .onLongPressGesture(minimumDuration: RoanaPresentation.gestureHold) {
                        debug.toggle()
                    }
            }
        }
    }
}

#Preview("Presentation Root") {
    PresentationRootView(frame: .sample)
}
