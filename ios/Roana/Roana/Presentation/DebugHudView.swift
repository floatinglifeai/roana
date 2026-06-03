// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import Foundation
import SwiftUI

/// Developer / testing surface. Mirrors Android's RoanaHudView. Camera frame is
/// not drawn here by default; a dim camera underlay can sit behind this view.
struct DebugHudView: View {
    let frame: PresentationFrame
    @Binding var settings: DebugHudSettings

    var body: some View {
        let style = RoanaPresentation.style(frame.command)
        HStack(spacing: 0) {
            layerRail

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("\(style.glyph) \(label(frame.command))")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(style.color, in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(Color(.sRGB, red: 0.02, green: 0.08, blue: 0.06))
                    Spacer()
                    Text(frame.reason)
                        .font(.system(size: 9, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 40)
                .padding(.horizontal, 8)

                // heatmap + overlays
                Canvas { ctx, size in
                    let g = RoanaPresentation.grid
                    let cw = size.width / CGFloat(g)
                    let ch = size.height / CGFloat(g)
                    let gap: CGFloat = 1.2

                    if settings.showDepth {
                        for r in 0 ..< g {
                            for c in 0 ..< g {
                                let rect = CGRect(x: CGFloat(c) * cw + gap / 2,
                                                  y: CGFloat(r) * ch + gap / 2,
                                                  width: cw - gap, height: ch - gap)
                                let color = RoanaPresentation.depthColor(frame.depthAt(r, c))
                                    .opacity(settings.showCameraUnderlay ? 0.57 : 1)
                                ctx.fill(Path(rect), with: .color(color))
                            }
                        }
                    } else if !settings.showCameraUnderlay {
                        var gridLines = Path()
                        for r in 0 ... g {
                            let y = CGFloat(r) * ch
                            gridLines.move(to: CGPoint(x: 0, y: y))
                            gridLines.addLine(to: CGPoint(x: size.width, y: y))
                        }
                        for c in 0 ... g {
                            let x = CGFloat(c) * cw
                            gridLines.move(to: CGPoint(x: x, y: 0))
                            gridLines.addLine(to: CGPoint(x: x, y: size.height))
                        }
                        ctx.stroke(gridLines, with: .color(RoanaPresentation.hex(0x334456)), lineWidth: 1)
                    }

                    // corridor path
                    if settings.showPath {
                        var path = Path()
                        let targetX = (CGFloat(style.pathTargetCol) + 0.5) * cw
                        path.move(to: CGPoint(x: size.width / 2, y: size.height))
                        path.addQuadCurve(to: CGPoint(x: targetX, y: size.height * 0.30),
                                          control: CGPoint(x: size.width / 2, y: size.height * 0.62))
                        ctx.stroke(path, with: .color(style.color),
                                   style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                    }

                    // detection boxes
                    if settings.showDetections {
                        for d in frame.detections {
                            let bw = CGFloat(d.width) * size.width
                            let bh = CGFloat(d.height) * size.height
                            let bx = CGFloat(d.centerX) * size.width - bw / 2
                            let by = CGFloat(d.centerY) * size.height - bh / 2
                            let box = CGRect(x: bx, y: by, width: bw, height: bh)
                            ctx.stroke(Path(box), with: .color(RoanaPresentation.detectionStroke),
                                       style: StrokeStyle(lineWidth: 2, dash: [6, 4]))

                            let label = "\(d.label) \(String(format: "%.2f", d.score))"
                            let chipWidth = CGFloat(label.count) * 6.4 + 12
                            let chip = CGRect(x: bx, y: max(0, by - 15), width: chipWidth, height: 15)
                            ctx.fill(Path(chip), with: .color(RoanaPresentation.detectionStroke))
                            let text = Text(label)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(.sRGB, red: 0.02, green: 0.13, blue: 0.11))
                            ctx.draw(text, at: CGPoint(x: chip.minX + 5, y: chip.midY), anchor: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(settings.showCameraUnderlay ? RoanaPresentation.hudCameraScrim : RoanaPresentation.hudBackground)

                // telemetry strip
                if settings.showTelemetry {
                    HStack(spacing: 1) {
                        let telemetry = frame.telemetry
                        ForEach(telemetry.indices, id: \.self) { index in
                            let item = telemetry[index]
                            VStack(spacing: 1) {
                                Text(item.0).font(.system(size: 7.5, design: .monospaced)).foregroundStyle(.secondary)
                                Text(item.1).font(.system(size: 13, weight: .medium, design: .monospaced))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(settings.showCameraUnderlay ? RoanaPresentation.hudCameraScrim : RoanaPresentation.hudBackground)
                        }
                    }
                    .background(Color(.sRGB, red: 0.12, green: 0.15, blue: 0.19))
                }
            }
        }
        .background(settings.showCameraUnderlay ? RoanaPresentation.hudCameraScrim : RoanaPresentation.hudBackground)
        .foregroundStyle(.white)
    }

    private var layerRail: some View {
        VStack(spacing: 8) {
            Spacer()
                .frame(height: 56)
            ForEach(DebugHudLayer.allCases) { layer in
                Button {
                    settings.toggle(layer)
                } label: {
                    Text(layer.label)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 56, height: 30)
                        .background(controlBackground(layer), in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(controlForeground(layer))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(layer.accessibilityLabel)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 72)
        .frame(maxHeight: .infinity)
        .background(Color(.sRGB, red: 0.04, green: 0.05, blue: 0.07))
    }

    private func controlBackground(_ layer: DebugHudLayer) -> Color {
        settings.isEnabled(layer)
            ? Color(.sRGB, red: 0.81, green: 0.91, blue: 0.82)
            : Color(.sRGB, red: 0.15, green: 0.19, blue: 0.23)
    }

    private func controlForeground(_ layer: DebugHudLayer) -> Color {
        settings.isEnabled(layer)
            ? Color(.sRGB, red: 0.02, green: 0.08, blue: 0.04)
            : Color(.sRGB, red: 0.67, green: 0.70, blue: 0.74)
    }

    private func label(_ c: RoanaCommand) -> String {
        switch c { case .straight: return "STRAIGHT"; case .left: return "LEFT"; case .right: return "RIGHT"; case .stop: return "STOP" }
    }
}

enum DebugHudLayer: CaseIterable, Hashable, Identifiable {
    case camera
    case depth
    case path
    case detections
    case telemetry

    var id: Self { self }

    var label: String {
        switch self {
        case .camera: return "CAM"
        case .depth: return "DEPTH"
        case .path: return "PATH"
        case .detections: return "BOX"
        case .telemetry: return "TEL"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .camera: return "Toggle camera underlay"
        case .depth: return "Toggle depth heatmap"
        case .path: return "Toggle corridor path"
        case .detections: return "Toggle detection boxes"
        case .telemetry: return "Toggle telemetry"
        }
    }
}

struct DebugHudSettings: Equatable {
    var showCameraUnderlay = false
    var showDepth = true
    var showPath = true
    var showDetections = true
    var showTelemetry = true

    mutating func toggle(_ layer: DebugHudLayer) {
        switch layer {
        case .camera:
            showCameraUnderlay.toggle()
        case .depth:
            showDepth.toggle()
        case .path:
            showPath.toggle()
        case .detections:
            showDetections.toggle()
        case .telemetry:
            showTelemetry.toggle()
        }
    }

    func isEnabled(_ layer: DebugHudLayer) -> Bool {
        switch layer {
        case .camera:
            showCameraUnderlay
        case .depth:
            showDepth
        case .path:
            showPath
        case .detections:
            showDetections
        case .telemetry:
            showTelemetry
        }
    }
}

#Preview("Debug HUD") {
    DebugHudPreview()
        .frame(width: 300, height: 560)
}

private struct DebugHudPreview: View {
    @State private var settings = DebugHudSettings()

    var body: some View {
        DebugHudView(frame: .sample, settings: $settings)
    }
}
