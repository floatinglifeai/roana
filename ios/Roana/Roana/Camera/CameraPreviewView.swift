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
}
