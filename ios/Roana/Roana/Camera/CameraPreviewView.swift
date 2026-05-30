// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 The Roana Authors.

import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.logOrientationUpdates = true
        return view
    }

    func updateUIView(_ view: PreviewContainerView, context: Context) {
        view.videoPreviewLayer.session = session
        view.updateOrientation()
    }
}

final class PreviewContainerView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    var logOrientationUpdates = false
    private var lastLoggedOrientation = ""

    override func layoutSubviews() {
        super.layoutSubviews()
        updateOrientation()
    }

    func updateOrientation() {
        guard let connection = videoPreviewLayer.connection else {
            return
        }

        let angle = rotationAngleForCurrentOrientation()
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
            logOrientation(angle: angle)
        }
    }

    private func rotationAngleForCurrentOrientation() -> CGFloat {
        switch window?.windowScene?.interfaceOrientation {
        case .landscapeLeft:
            0
        case .landscapeRight:
            180
        case .portraitUpsideDown:
            270
        case .portrait, .unknown, .none:
            90
        @unknown default:
            90
        }
    }

    private func logOrientation(angle: CGFloat) {
        guard logOrientationUpdates else {
            return
        }

        let interfaceOrientation = window?.windowScene?.interfaceOrientation.logValue ?? "unknown"
        let key = "\(interfaceOrientation):\(Int(angle))"
        guard key != lastLoggedOrientation else {
            return
        }
        lastLoggedOrientation = key
        print("roana_ios_orientation source=preview interface=\(interfaceOrientation) angle=\(Int(angle))")
    }
}

private extension UIInterfaceOrientation {
    var logValue: String {
        switch self {
        case .portrait:
            "portrait"
        case .portraitUpsideDown:
            "portrait_upside_down"
        case .landscapeLeft:
            "landscape_left"
        case .landscapeRight:
            "landscape_right"
        case .unknown:
            "unknown"
        @unknown default:
            "unknown"
        }
    }
}
