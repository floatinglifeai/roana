// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import SwiftUI

/// Default real-user surface. Mirrors Android's RoanaAmbientView. Near-black,
/// low-power; one large command glyph + caption + an "alive" pulse. STOP draws a
/// red edge. The guidance that matters is speech / haptics, not this screen.
struct AmbientView: View {
    let command: RoanaCommand
    @State private var pulse = false

    var body: some View {
        let style = RoanaPresentation.style(command)
        ZStack {
            RoanaPresentation.ambientBackground.ignoresSafeArea()

            Circle()
                .stroke(style.color, lineWidth: 2)
                .frame(width: 160, height: 160)
                .scaleEffect(pulse ? 1.05 : 0.82)
                .opacity(pulse ? 0.40 : 0.12)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: pulse)

            VStack(spacing: 18) {
                Text(style.glyph)
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(style.color)
                    .shadow(color: style.color.opacity(0.7), radius: 14)
                Text(style.caption)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(.sRGB, red: 0.87, green: 0.90, blue: 0.93))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(RoanaPresentation.stopEdge.opacity(command == .stop ? 0.55 : 0), lineWidth: 6)
                .ignoresSafeArea()
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style.caption)
        .onAppear { pulse = true }
    }
}
