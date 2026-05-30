// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var camera: CameraSessionController

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()
                .overlay(permissionOverlay)

            diagnosticsPanel
                .padding(16)
        }
        .background(Color.black)
        .foregroundStyle(.white)
        .task {
            camera.start()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            camera.stop()
        }
    }

    @ViewBuilder
    private var permissionOverlay: some View {
        switch camera.authorization.state {
        case .authorized:
            EmptyView()
        case .notDetermined:
            statusOverlay("Requesting camera permission")
        case .denied, .restricted:
            statusOverlay("Camera permission required")
        }
    }

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(camera.statusText)
                .font(.headline)
            Text("Auth: \(camera.authorization.logValue)")
            Text("Device: \(camera.deviceDiagnostics.deviceModel)")
            Text("iOS: \(camera.deviceDiagnostics.systemVersion)")
            Text("Thermal: \(camera.deviceDiagnostics.thermalState)")
            Text("Launch: \(camera.deviceDiagnostics.launchUptimeSeconds, specifier: "%.1f")s")
            Text("Frame: \(camera.latestFrameSummary)")
        }
        .font(.system(size: 13, weight: .medium, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(12)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func statusOverlay(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "camera")
                .font(.system(size: 36, weight: .semibold))
            Text(message)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.86))
    }
}

#Preview {
    ContentView(camera: CameraSessionController())
}
