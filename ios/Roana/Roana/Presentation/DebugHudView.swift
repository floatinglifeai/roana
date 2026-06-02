// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import SwiftUI

/// Developer / testing surface. Mirrors Android's RoanaHudView. Camera frame is
/// not drawn here by default; a dim camera underlay can sit behind this view.
struct DebugHudView: View {
    let frame: PresentationFrame

    var body: some View {
        let style = RoanaPresentation.style(frame.command)
        VStack(spacing: 0) {
            // command chip + reason
            HStack(spacing: 6) {
                Text("\(style.glyph) \(label(frame.command))")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(style.color, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(Color(.sRGB, red: 0.02, green: 0.08, blue: 0.06))
                Spacer()
                Text(frame.reason)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)

            // heatmap + overlays
            Canvas { ctx, size in
                let g = RoanaPresentation.grid
                let cw = size.width / CGFloat(g)
                let ch = size.height / CGFloat(g)
                let gap: CGFloat = 1.2

                for r in 0 ..< g {
                    for c in 0 ..< g {
                        let rect = CGRect(x: CGFloat(c) * cw + gap / 2,
                                          y: CGFloat(r) * ch + gap / 2,
                                          width: cw - gap, height: ch - gap)
                        ctx.fill(Path(rect), with: .color(RoanaPresentation.depthColor(frame.depthAt(r, c))))
                    }
                }

                // corridor path
                var path = Path()
                let targetX = (CGFloat(style.pathTargetCol) + 0.5) * cw
                path.move(to: CGPoint(x: size.width / 2, y: size.height))
                path.addQuadCurve(to: CGPoint(x: targetX, y: size.height * 0.30),
                                  control: CGPoint(x: size.width / 2, y: size.height * 0.62))
                ctx.stroke(path, with: .color(style.color),
                           style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))

                // detection boxes
                for d in frame.detections {
                    let bw = CGFloat(d.width) * size.width
                    let bh = CGFloat(d.height) * size.height
                    let bx = CGFloat(d.centerX) * size.width - bw / 2
                    let by = CGFloat(d.centerY) * size.height - bh / 2
                    let box = CGRect(x: bx, y: by, width: bw, height: bh)
                    ctx.stroke(Path(box), with: .color(RoanaPresentation.detectionStroke),
                               style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    let text = Text("\(d.label) \(String(format: "%.2f", d.score))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(.sRGB, red: 0.02, green: 0.13, blue: 0.11))
                    ctx.draw(text, at: CGPoint(x: bx + 28, y: by - 7), anchor: .leading)
                }
            }
            .background(RoanaPresentation.hudBackground)

            // telemetry strip
            HStack(spacing: 1) {
                ForEach(frame.telemetry, id: \.0) { k, v in
                    VStack(spacing: 1) {
                        Text(k).font(.system(size: 7.5, design: .monospaced)).foregroundStyle(.secondary)
                        Text(v).font(.system(size: 13, weight: .medium, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(RoanaPresentation.hudBackground)
                }
            }
            .background(Color(.sRGB, red: 0.12, green: 0.15, blue: 0.19))
        }
        .background(RoanaPresentation.hudBackground)
        .foregroundStyle(.white)
    }

    private func label(_ c: RoanaCommand) -> String {
        switch c { case .straight: return "STRAIGHT"; case .left: return "LEFT"; case .right: return "RIGHT"; case .stop: return "STOP" }
    }
}

#Preview("Debug HUD") {
    DebugHudView(frame: .sample).frame(width: 300, height: 560)
}
